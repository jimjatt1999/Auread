import SwiftUI
import UniformTypeIdentifiers // Needed for UTType
import ReadiumShared // <-- Add
import ReadiumStreamer // <-- Add
import ReadiumInternal // <-- Add
import ReadiumOPDS // <-- Add (for DefaultHTTPClient)

struct HomeView: View {
    // Remove redundant AppStorage and State - Use BookLibrary as single source of truth
    // @AppStorage("books") private var booksData: Data = Data()
    // @State private var books: [Book] = [] // Use Book directly
    @EnvironmentObject var bookLibrary: BookLibrary

    @State private var documentPickerIsPresented = false
    @State private var selectedBookForReader: Book? // Use Book directly
    @State private var readerIsPresented = false
    @State private var searchText = "" // State for search text

    // Computed property for filtering based on search text - Filter bookLibrary directly
    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return bookLibrary.books
        } else {
            return bookLibrary.books.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.author ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            List {
                // Use filteredBooks here
                ForEach(filteredBooks) { book in
                    // Get progress for the current book
                    let progress = bookLibrary.getProgression(for: book.id)
                    BookItemView(
                        title: book.title,
                        author: book.author,
                        coverImagePath: book.coverImagePath,
                        progress: progress // Pass progress to the view
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBookForReader = book
                        // Attempt to gain access before presenting reader
                        // Note: This access is short-lived, ReaderView needs its own.
                        _ = book.getURL()?.startAccessingSecurityScopedResource()
                        readerIsPresented = true
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                }
                .onDelete(perform: deleteBook) // Allow swipe to delete

                // Placeholder if no books are added or filtered out
                if filteredBooks.isEmpty {
                    if bookLibrary.books.isEmpty {
                        // Show initial prompt if library is completely empty
                        VStack {
                            Spacer()
                            Text("Library is empty.")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Button("Add your first EPUB") {
                                documentPickerIsPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .listRowSeparator(.hidden)
                    } else {
                        // Show if search yields no results
                        Text("No books found matching \"\(searchText)\".")
                            .foregroundColor(.gray)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain) // Use plain style to remove default list background/inset
            .navigationTitle("All Books") // Match screenshot title
            .searchable(text: $searchText, prompt: "Search books by title or author") // Add search bar
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        documentPickerIsPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton() // Add standard Edit button for deletion
                }
            }
            .fileImporter(
                isPresented: $documentPickerIsPresented,
                allowedContentTypes: [UTType.epub],
                allowsMultipleSelection: false
            ) { result in
                // Wrap the async function call in a Task
                Task {
                    await handleFileImport(result: result)
                }
            }
            .fullScreenCover(item: $selectedBookForReader) { book in
                // Resolve URL just before presenting ReaderView
                if let url = book.getURL() {
                    // Get the initial locator from BookLibrary
                    let initialLocator = bookLibrary.getPosition(for: book.id)
                    ReaderView(fileURL: url, bookID: book.id, bookLibrary: bookLibrary, initialLocator: initialLocator)
                        .environmentObject(bookLibrary)
                } else {
                    // Handle error: Could not resolve URL from bookmark
                    Text("Error: Could not open book. Please try importing it again.")
                        .padding()
                        .onAppear {
                            // Attempt to remove the faulty book entry?
                        }
                }
            }
        }
    }

    // Make the function async
    private func handleFileImport(result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed initial access for bookmark: \(url)")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() } // Stop access after scope exits

            do {
                // Generate a new UUID for this book (used for saving cover)
                let newID = UUID()
                // Create bookmark data without .withSecurityScope for iOS
                let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

                // --- Metadata Extraction ---
                var extractedTitle = url.deletingPathExtension().lastPathComponent
                var extractedAuthor: String? = nil
                var extractedCoverPath: String? = nil

                // Create temporary Readium components for metadata extraction
                let tempHttpClient = DefaultHTTPClient()
                let tempAssetRetriever = AssetRetriever(httpClient: tempHttpClient)
                let tempOpener = PublicationOpener(parser: EPUBParser(), contentProtections: [])

                guard let absoluteURL = url.anyURL.absoluteURL else {
                    addBookToList(id: newID, title: extractedTitle, author: extractedAuthor, coverImagePath: extractedCoverPath, bookmarkData: bookmarkData)
                    return
                }

                switch await tempAssetRetriever.retrieve(url: absoluteURL) {
                case .success(let asset):
                    switch await tempOpener.open(asset: asset, allowUserInteraction: false, sender: nil) {
                    case .success(let publication):
                        extractedTitle = publication.metadata.title ?? extractedTitle
                        extractedAuthor = publication.metadata.authors.first?.name
                        // Extract cover image (UIImage?) using Readium API
                        let coverResult = await publication.cover()
                        switch coverResult {
                        case .success(let uiImageOptional):
                            if let uiImage = uiImageOptional,
                               let imageData = uiImage.pngData(),
                               let path = saveCoverData(imageData, bookID: newID) {
                                extractedCoverPath = path
                            }
                        case .failure(let error):
                            print("Cover extract error: \(error)")
                        }
                    case .failure:
                        break
                    }
                case .failure:
                    break
                }
                // --- End Metadata Extraction ---

                // Add book using extracted metadata and cover
                addBookToList(id: newID, title: extractedTitle, author: extractedAuthor, coverImagePath: extractedCoverPath, bookmarkData: bookmarkData)

            } catch {
                print("Error creating bookmark data for \(url): \(error)")
            }

        case .failure(let error):
            print("Error picking file: \(error.localizedDescription)")
        }
    }

    // Helper function to add book and save
    private func addBookToList(id: UUID = UUID(), title: String, author: String?, coverImagePath: String?, bookmarkData: Data) {
        let newBook = Book(
            id: id,
            title: title,
            author: author,
            fileURLBookmark: bookmarkData,
            coverImagePath: coverImagePath
        )
        // Avoid duplicates - Check bookLibrary directly
        if !bookLibrary.books.contains(where: { $0.fileURLBookmark == newBook.fileURLBookmark }) {
            // Add to list on main thread - Call bookLibrary method
            DispatchQueue.main.async {
                bookLibrary.addBook(newBook) // Add directly to BookLibrary
            }
        } else {
            print("Book already in library.")
        }
    }

    // Delete book from the list - Operate on bookLibrary directly
    private func deleteBook(at offsets: IndexSet) {
        // Get the actual books to remove based on the filtered list indices
        let booksToRemove = offsets.map { filteredBooks[$0] }
        
        // Find the corresponding indices in the main bookLibrary.books array
        let indicesInLibrary = booksToRemove.compactMap { bookToRemove in
            bookLibrary.books.firstIndex(where: { $0.id == bookToRemove.id })
        }
        
        // Ensure indices are valid before removing
        guard !indicesInLibrary.isEmpty else { return }
        
        // Create an IndexSet from the library indices
        let indexSetInLibrary = IndexSet(indicesInLibrary)
        
        // Call BookLibrary's delete method
        bookLibrary.deleteBook(at: indexSetInLibrary)
    }

    // Helper to save cover data to disk and return file path
    private func saveCoverData(_ data: Data, bookID: UUID) -> String? {
        let filename = "cover_\(bookID.uuidString).png"
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsURL.appendingPathComponent(filename)
            do {
                try data.write(to: fileURL)
                return fileURL.path
            } catch {
                print("Error saving cover image: \(error)")
                return nil
            }
        }
        return nil
    }
}

// Preview
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}

// Helper extension for EPUB UTType if needed (Xcode 13+)
// If using older Xcode, you might need a different approach or define the string directly.
extension UTType {
    static var epub: UTType {
        UTType(importedAs: "org.idpf.epub-container")
    }
} 
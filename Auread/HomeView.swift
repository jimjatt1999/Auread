import SwiftUI
import UniformTypeIdentifiers // Needed for UTType
import ReadiumShared // <-- Add
import ReadiumStreamer // <-- Add
import ReadiumInternal // <-- Add
import ReadiumOPDS // <-- Add (for DefaultHTTPClient)

struct HomeView: View {
    @EnvironmentObject var bookLibrary: BookLibrary
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var documentPickerIsPresented = false
    @State private var selectedBookForReader: Book?
    @State private var navigateToReader = false
    @State private var searchText = ""
    @State private var selectedTab = 0 // 0 = Library, 1 = Highlights

    // Computed property for filtering based on search text
    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return bookLibrary.books
        } else {
            return bookLibrary.books.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                ($0.author ?? "").localizedCaseInsensitiveContains(searchText) 
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Library Tab
            libraryTab
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(0)
            
            // Highlights Tab
            HighlightTimelineView()
                .tabItem {
                    Label("Highlights", systemImage: "highlighter")
                }
                .tag(1)
        }
        .opacity(Environment(\.hideTabBar).wrappedValue ? 0 : 1) // Hide tab bar when needed
    }
    
    var libraryTab: some View {
        NavigationView {
            VStack(spacing: 0) {
                if filteredBooks.isEmpty {
                    emptyLibraryView
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
                        ], spacing: 24) {
                ForEach(filteredBooks) { book in
                                ModernBookItemView(book: book)
                                    .frame(height: 250)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBookForReader = book
                        _ = book.getURL()?.startAccessingSecurityScopedResource()
                                        navigateToReader = true
                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteBook(book: book)
                                        } label: {
                                            Label("Delete Book", systemImage: "trash")
                                        }
                                    }
                            }
                            }
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        documentPickerIsPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $documentPickerIsPresented,
                allowedContentTypes: [UTType.epub],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await handleFileImport(result: result)
                }
            }
            .background(
                NavigationLink(
                    destination: buildReaderDestination()
                        .navigationBarHidden(true)
                        .hideTabBar(),
                    isActive: $navigateToReader
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
    }
    
    @ViewBuilder
    private func buildReaderDestination() -> some View {
        if let book = selectedBookForReader,
           let url = book.getURL() {
            
                    let initialLocator = bookLibrary.getPosition(for: book.id)
            
            ReaderView(fileURL: url,
                      bookID: book.id,
                      bookLibrary: bookLibrary,
                      settingsManager: settingsManager,
                      initialLocator: initialLocator)
                        .environmentObject(bookLibrary)
                .environmentObject(settingsManager)
                .navigationBarHidden(true)
                        .onAppear {
                    if let loc = initialLocator {
                        print("[HomeView] Reader navigating with:")
                        print("  - Href: \(loc.href)")
                        print("  - Progression: \(loc.locations.progression ?? -1)")
                    }
                }
                .onDisappear {
                    navigateToReader = false
                    selectedBookForReader = nil
                }
        } else {
            Text("Error: Book not available")
                .onAppear {
                    navigateToReader = false
                    selectedBookForReader = nil
                }
        }
    }
    
    var emptyLibraryView: some View {
        VStack {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.7))
                .padding()
            
            Text("Your library is empty")
                .font(.title2)
                .foregroundColor(.primary)
                .padding(.top)
            
            Text("Add your first book to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            Button {
                documentPickerIsPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Book")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(20)
                .shadow(radius: 2, y: 1)
            }
            .padding(.top, 30)
            
            Spacer()
        }
    }

    // Helper function to delete a specific book object
    private func deleteBook(book: Book) {
        // Find the index in the main library array
        if let index = bookLibrary.books.firstIndex(where: { $0.id == book.id }) {
            // Call BookLibrary's delete method using an IndexSet
            bookLibrary.deleteBook(at: IndexSet(integer: index))
        } else {
            print("Error: Could not find book \(book.title) to delete.")
        }
    }
    
    // Same file import handling as before
    private func handleFileImport(result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed initial access for bookmark: \(url)")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let newID = UUID()
                let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

                var extractedTitle = url.deletingPathExtension().lastPathComponent
                var extractedAuthor: String? = nil
                var extractedCoverPath: String? = nil

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

                addBookToList(id: newID, title: extractedTitle, author: extractedAuthor, coverImagePath: extractedCoverPath, bookmarkData: bookmarkData)

            } catch {
                print("Error creating bookmark data for \(url): \(error)")
            }

        case .failure(let error):
            print("Error picking file: \(error.localizedDescription)")
        }
    }

    private func addBookToList(id: UUID = UUID(), title: String, author: String?, coverImagePath: String?, bookmarkData: Data) {
        let newBook = Book(
            id: id,
            title: title,
            author: author,
            fileURLBookmark: bookmarkData,
            coverImagePath: coverImagePath
        )
        
        if !bookLibrary.books.contains(where: { $0.fileURLBookmark == newBook.fileURLBookmark }) {
            DispatchQueue.main.async {
                bookLibrary.addBook(newBook)
            }
        } else {
            print("Book already in library.")
        }
    }

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

struct ModernBookItemView: View {
    let book: Book
    
    @EnvironmentObject var bookLibrary: BookLibrary
    
    var progress: Double? {
        return bookLibrary.getProgression(for: book.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover Image
            ZStack(alignment: .bottomLeading) {
                if let path = book.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    // Placeholder with gradient background
                    LinearGradient(
                        colors: [.gray.opacity(0.7), .gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.white.opacity(0.6))
                    )
                }
                
                // Progress indicator at the bottom of the cover
                if let progress = progress, progress > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                    .frame(height: 4)
                }
            }
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            
            // Book info
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.top, 6)
                
                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Progress as text
                if let progress = progress, progress > 0 {
                    Text("\(Int(progress * 100))% read")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 4)
            
            Spacer()
        }
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
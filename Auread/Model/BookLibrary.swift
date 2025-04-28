import Foundation
import SwiftUI
import ReadiumShared // Needed for Locator

class BookLibrary: ObservableObject {
    @Published var books: [Book] = []
    
    // URL for storing the library data
    private var booksFileURL: URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Cannot access Application Support directory.") // Should not happen
        }
        let directoryURL = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Auread")
        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        return directoryURL.appendingPathComponent("library.json")
    }
    
    init() {
        print("BookLibrary: Initializing...")
        loadBooks()
    }
    
    private func loadBooks() {
        let fileURL = booksFileURL
        print("BookLibrary: Attempting to load books from file: \(fileURL.path)")
        // Check if file exists before trying to read
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("BookLibrary: Library file not found. Initializing with empty books array.")
            books = []
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            books = try JSONDecoder().decode([Book].self, from: data)
            print("BookLibrary: Successfully loaded \(books.count) books from file.")
            // Optional: Log details of loaded positions
            /*
            for book in books {
                if let data = book.lastLocatorData, let pos = try? JSONDecoder().decode(BookPosition.self, from: data) {
                    print("  - Book \(book.id): Loaded position Href=\(pos.href) Prog=\(pos.progression)")
                } else {
                    print("  - Book \(book.id): No position data or decoding failed.")
                }
            }
            */
        } catch {
            print("BookLibrary: FATAL ERROR loading books from file - URL: \(fileURL.path), Error: \(error)")
            books = [] // Reset if decoding fails
        }
    }
    
    private func saveBooks() {
        let fileURL = booksFileURL
        print("BookLibrary: Attempting to save books to file: \(fileURL.path)")
        do {
            let dataToSave = try JSONEncoder().encode(books)
            // Use atomic write for better safety
            try dataToSave.write(to: fileURL, options: .atomic)
            print("BookLibrary: Successfully saved books data (\(dataToSave.count) bytes) to file.")
        } catch {
            print("BookLibrary: FATAL ERROR saving books to file - URL: \(fileURL.path), Error: \(error)")
        }
    }
    
    func addBook(_ book: Book) {
        books.append(book)
        saveBooks()
    }
    
    func deleteBook(at indexSet: IndexSet) {
        books.remove(atOffsets: indexSet)
        saveBooks()
    }
    
    func updateBookProgress(id: UUID, locatorData: Data?) {
        if let index = books.firstIndex(where: { $0.id == id }) {
            var updatedBook = books[index]
            updatedBook.lastLocatorData = locatorData
            books[index] = updatedBook
            saveBooks()
        }
    }
    
    func getBook(id: UUID) -> Book? {
        return books.first(where: { $0.id == id })
    }
} 
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
    
    // --- NEW Properties for Bookmarks/Highlights --- 
    @Published var bookmarks: [Bookmark] = []
    @Published var highlights: [Highlight] = [] // Assuming Highlight exists or will be added
    private let bookmarksFilePath: URL
    private let highlightsFilePath: URL // Assuming highlights are saved separately
    
    // Add a lock for thread safety when modifying arrays/saving
    private let dataLock = NSLock()
    
    init() {
        print("BookLibrary: Initializing...")
        
        // Determine file paths FIRST
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Cannot access Application Support directory.")
        }
        let directoryURL = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Auread")
        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        
        // Initialize path properties BEFORE calling load methods
        self.bookmarksFilePath = directoryURL.appendingPathComponent("bookmarks.json")
        self.highlightsFilePath = directoryURL.appendingPathComponent("highlights.json")
        
        // Now that all properties are initialized, load the data
        loadBooks() 
        loadBookmarks()
        loadHighlights() // Call method to load highlights
        
        print("BookLibrary: Initialization complete.")
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
    
    // MARK: - Bookmarks
    
    // Function to add a bookmark (now accepts title)
    func addBookmark(for bookID: UUID, locator: Locator, title: String?) {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }) else { return }
        
        // Ensure we don't add duplicates based on locator
        if findBookmark(for: bookID, near: locator) != nil {
            print("Bookmark already exists near this location.")
            return
        }

        // Create a Codable BookPosition from the Locator
        let position = BookPosition(from: locator)

        // Encode the BookPosition to Data
        guard let locatorData = try? JSONEncoder().encode(position) else {
            print("Error encoding BookPosition for bookmark.")
            return
        }

        // Use the explicitly passed title (from ViewModel) first
        let bookmarkTitle = title ?? position.resourceTitle // Fallback to title from BookPosition if ViewModel's is nil

        let newBookmark = Bookmark(bookID: bookID, locatorData: locatorData, chapterTitle: bookmarkTitle)
        
        dataLock.lock()
        bookmarks.append(newBookmark)
        dataLock.unlock()
        
        saveBookmarks() // Save changes
        print("Bookmark added with title: \(bookmarkTitle ?? "nil")")
    }

    // Function to get bookmarks for a specific book
    func getBookmarks(for bookID: UUID) -> [Bookmark] {
        dataLock.lock()
        defer { dataLock.unlock() }
        return bookmarks.filter { $0.bookID == bookID }
    }

    // Function to delete a bookmark by its ID
    func deleteBookmark(id: UUID) {
        dataLock.lock()
        bookmarks.removeAll { $0.id == id }
        // Optional: Also remove from book's internal array
        // if let bookIndex = books.firstIndex(where: { $0.bookmarks.contains(where: { $0.id == id }) }) {
        //     books[bookIndex].bookmarks.removeAll { $0.id == id }
        // }
        dataLock.unlock()
        saveBookmarks() // Save changes
        print("Bookmark deleted: \(id)")
    }

    // Function to find a bookmark near a specific locator (tolerance might be needed)
    // This needs a robust way to compare Locators or their key properties.
    // For now, a simple comparison (needs refinement based on Locator structure)
    func findBookmark(for bookID: UUID, near locator: Locator) -> Bookmark? {
        dataLock.lock()
        defer { dataLock.unlock() }
        
        let bookBookmarks = bookmarks.filter { $0.bookID == bookID }
        let targetPosition = BookPosition(from: locator) // Create target BookPosition
        
        // Decode stored BookPosition for comparison
        for bookmark in bookBookmarks {
            if let storedPosition = try? JSONDecoder().decode(BookPosition.self, from: bookmark.locatorData) {
                // Compare BookPosition properties (adjust tolerance as needed)
                if storedPosition.href == targetPosition.href && 
                   abs(storedPosition.totalProgression - targetPosition.totalProgression) < 0.001 { // Tolerance
                    return bookmark
                }
            }
        }
        return nil
    }
    
    // --- Persistence for Bookmarks --- 
    private func saveBookmarks() {
        dataLock.lock()
        let bookmarksToSave = bookmarks // Capture the current state inside the lock
        dataLock.unlock()
        
        Task {
            do {
                let data = try JSONEncoder().encode(bookmarksToSave)
                try data.write(to: bookmarksFilePath, options: .atomic)
                print("Bookmarks saved successfully to \(bookmarksFilePath.path)")
            } catch {
                print("Error saving bookmarks: \(error)")
            }
        }
    }

    private func loadBookmarks() {
        // Check path directly
        guard FileManager.default.fileExists(atPath: bookmarksFilePath.path) else {
            print("Bookmarks file not found at \(bookmarksFilePath.path), starting fresh.")
            self.bookmarks = [] // Ensure bookmarks is initialized even if file doesn't exist
            return
        }
        
        do {
            let data = try Data(contentsOf: bookmarksFilePath)
            let loadedBookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
            
            dataLock.lock()
            self.bookmarks = loadedBookmarks
            dataLock.unlock()
            
            print("Bookmarks loaded successfully: \(loadedBookmarks.count) bookmarks")
            
            // Optional: If you still store bookmarks inside Book objects, reconcile here.

        } catch {
            print("Error loading bookmarks: \(error). Starting fresh.")
            self.bookmarks = [] // Start fresh if loading fails
        }
    }
    
    // MARK: - Highlights
    
    // --- Persistence for Highlights --- 
    private func saveHighlights() {
        dataLock.lock()
        let highlightsToSave = highlights // Capture the current state inside the lock
        dataLock.unlock()
        
        Task {
            do {
                let data = try JSONEncoder().encode(highlightsToSave)
                try data.write(to: highlightsFilePath, options: .atomic)
                print("Highlights saved successfully to \(highlightsFilePath.path)")
            } catch {
                print("Error saving highlights: \(error)")
            }
        }
    }

    private func loadHighlights() {
        guard FileManager.default.fileExists(atPath: highlightsFilePath.path) else {
            print("Highlights file not found at \(highlightsFilePath.path), starting fresh.")
            self.highlights = [] // Ensure highlights is initialized even if file doesn't exist
            return
        }
        
        do {
            let data = try Data(contentsOf: highlightsFilePath)
            let loadedHighlights = try JSONDecoder().decode([Highlight].self, from: data)
            
            dataLock.lock()
            self.highlights = loadedHighlights
            dataLock.unlock()
            
            print("Highlights loaded successfully: \(loadedHighlights.count) highlights")

        } catch {
            print("Error loading highlights: \(error). Starting fresh.")
            self.highlights = [] // Start fresh if loading fails
        }
    }

    // Placeholder - Actual highlighting needs text selection interaction
    func addHighlight(for bookID: UUID, locator: Locator, text: String) {
        // Find the book index - although maybe highlights shouldn't be tied to the book object?
        // For now, let's assume highlights are managed in the top-level array like bookmarks.
        // guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        
        // Create BookPosition and encode it
        if locator.href.string != "about:blank" {
            let position = BookPosition(from: locator)
            if let locatorData = try? JSONEncoder().encode(position) {
                // Create the Highlight object
                let newHighlight = Highlight(bookID: bookID, locatorData: locatorData, selectedText: text)
                
                // Add to the top-level highlights array
                dataLock.lock()
                highlights.append(newHighlight)
                dataLock.unlock()
                
                // Save changes
                saveHighlights()
                
                print("Highlight added for book \(bookID) at \(position.href): \(text)")
            } else {
                 print("Error encoding BookPosition for highlight.")
            }
         } else {
             print("Attempted to add highlight with invalid locator href.")
         }
    }
    
    func getHighlights(for bookID: UUID) -> [Highlight] {
        // Filter the main highlights array
        dataLock.lock()
        defer { dataLock.unlock() }
        return highlights.filter { $0.bookID == bookID }
    }
    
    // TODO: Add deleteHighlight function later
    func deleteHighlight(id: UUID) {
        dataLock.lock()
        highlights.removeAll { $0.id == id }
        dataLock.unlock()
        saveHighlights() // Save changes
        print("Highlight deleted: \(id)")
    }
    
} 
import Foundation
import SwiftUI

// Book model representing an EPUB book in the library
struct Book: Identifiable, Codable {
    let id: UUID
    let title: String
    let author: String?
    let fileURLBookmark: Data
    let coverImagePath: String?
    var lastLocatorData: Data? // Stores serialized Locator for reading position
    var addedDate: Date
    // Add arrays for bookmarks and highlights
    var bookmarks: [Bookmark] = []
    var highlights: [Highlight] = []
    
    // Initialize with necessary data (including new arrays)
    init(id: UUID = UUID(), title: String, author: String? = nil, fileURLBookmark: Data, coverImagePath: String? = nil, lastLocatorData: Data? = nil, addedDate: Date = Date(), bookmarks: [Bookmark] = [], highlights: [Highlight] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.fileURLBookmark = fileURLBookmark
        self.coverImagePath = coverImagePath
        self.lastLocatorData = lastLocatorData
        self.addedDate = addedDate
        // Initialize new arrays
        self.bookmarks = bookmarks
        self.highlights = highlights
    }
    
    func getURL() -> URL? {
        do {
            var isStale = false
            // Resolve bookmark to URL
            let url = try URL(resolvingBookmarkData: fileURLBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                print("Warning: Bookmark is stale for \(title)")
            }
            return url
        } catch {
            print("Error resolving bookmark for \(title): \(error)")
            return nil
        }
    }
} 
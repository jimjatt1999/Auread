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
    
    // Initialize with necessary data
    init(id: UUID = UUID(), title: String, author: String? = nil, fileURLBookmark: Data, coverImagePath: String? = nil, lastLocatorData: Data? = nil, addedDate: Date = Date()) {
        self.id = id
        self.title = title
        self.author = author
        self.fileURLBookmark = fileURLBookmark
        self.coverImagePath = coverImagePath
        self.lastLocatorData = lastLocatorData
        self.addedDate = addedDate
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
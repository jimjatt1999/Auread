import Foundation
import ReadiumShared // For Locator type reference
import ReadiumInternal // For anyURL extension

// A Codable struct to represent reading position
// Converts between Readium's Locator and our serializable format
struct BookPosition: Codable {
    // Store complete required information for reading position
    // Use totalProgression for overall book progress
    var totalProgression: Double 
    var position: Int?
    var resourceTitle: String?
    var href: String // Store the actual resource href
    
    // Create from a Readium Locator
    init(from locator: Locator) {
        // Store overall book progression
        self.totalProgression = locator.locations.totalProgression ?? 0.0 
        self.position = locator.locations.position
        self.resourceTitle = locator.title
        // Store the actual resource path
        self.href = locator.href.string
    }
    
    // Create a new locator with the stored position
    func asLocator() -> Locator {
        // First try to create a proper URL from the stored href
        if let url = URL(string: href) {
            return Locator(
                href: url,
                mediaType: MediaType.html,
                title: resourceTitle,
                locations: Locator.Locations(
                    // Use totalProgression here as well
                    totalProgression: totalProgression, 
                    position: position
                )
            )
        } else {
            // Fallback to a default URL if necessary
            let url = URL(string: "about:blank")!
            return Locator(
                href: url,
                mediaType: MediaType.html,
                title: resourceTitle,
                locations: Locator.Locations(
                    // Use totalProgression here as well
                    totalProgression: totalProgression, 
                    position: position
                )
            )
        }
    }
}

// Extension to BookLibrary for handling position conversion
extension BookLibrary {
    // Save position for a book using BookPosition
    func savePosition(for bookID: UUID, locator: Locator) {
        // Only save if we have a valid locator with a real resource URL
        if locator.href.string != "about:blank" {
            let position = BookPosition(from: locator)
            // Log total progression
            print("Saving position: \(position.href) at totalProgression \(position.totalProgression)")
            if let positionData = try? JSONEncoder().encode(position) {
                updateBookProgress(id: bookID, locatorData: positionData)
            }
        }
    }
    
    // Get position for a book as a Locator
    func getPosition(for bookID: UUID) -> Locator? {
        if let book = getBook(id: bookID),
           let positionData = book.lastLocatorData,
           let position = try? JSONDecoder().decode(BookPosition.self, from: positionData) {
            let locator = position.asLocator()
            // Log total progression
            print("Restoring position: \(position.href) at totalProgression \(position.totalProgression)")
            return locator
        }
        return nil
    }
    
    // New method to get just the progression value
    func getProgression(for bookID: UUID) -> Double? {
        if let book = getBook(id: bookID),
           let positionData = book.lastLocatorData,
           let position = try? JSONDecoder().decode(BookPosition.self, from: positionData) {
            // Return totalProgression, ensuring it's between 0.0 and 1.0
            return max(0.0, min(1.0, position.totalProgression))
        }
        return nil // Return nil if no position is saved or decoding fails
    }
} 

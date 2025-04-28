import Foundation

struct Highlight: Identifiable, Codable, Hashable {
    let id: UUID
    let bookID: UUID
    let locatorData: Data // Stores encoded BookPosition of the highlight's location
    let selectedText: String // Might be useful for display, though locator.text.highlight is primary
    let creationDate: Date
    var color: String // Name of the color (e.g., "yellow", "blue", "green", "pink")
    var note: String? // Optional user note
    
    // Default color constant
    static let defaultColor = "yellow"

    init(id: UUID = UUID(), 
         bookID: UUID, 
         locatorData: Data, 
         selectedText: String, 
         creationDate: Date = Date(),
         color: String = Highlight.defaultColor, // Default to yellow
         note: String? = nil) {
        self.id = id
        self.bookID = bookID
        self.locatorData = locatorData
        self.selectedText = selectedText
        self.creationDate = creationDate
        self.color = color
        self.note = note
    }
} 
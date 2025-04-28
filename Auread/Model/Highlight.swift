import Foundation

struct Highlight: Identifiable, Codable, Hashable {
    let id: UUID
    let bookID: UUID
    let locatorData: Data // Stores encoded BookPosition of the highlight's location
    let selectedText: String
    let creationDate: Date
    
    init(id: UUID = UUID(), bookID: UUID, locatorData: Data, selectedText: String, creationDate: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.locatorData = locatorData
        self.selectedText = selectedText
        self.creationDate = creationDate
    }
} 
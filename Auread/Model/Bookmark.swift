import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let bookID: UUID // To associate with the book
    let locatorData: Data // Stores encoded BookPosition
    let creationDate: Date
    var chapterTitle: String?
    
    // Minimal required init
    init(id: UUID = UUID(), bookID: UUID, locatorData: Data, creationDate: Date = Date(), chapterTitle: String? = nil) {
        self.id = id
        self.bookID = bookID
        self.locatorData = locatorData
        self.creationDate = creationDate
        self.chapterTitle = chapterTitle
    }
    
    // Implement Equatable based on ID
    static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
        lhs.id == rhs.id
    }
} 
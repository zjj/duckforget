import Foundation
import SwiftData

@Model
final class TagItem {
    var id: UUID
    var name: String
    var createdAt: Date
    var sortOrder: Int

    var notes: [NoteItem]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        notes: [NoteItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.notes = notes
    }
}

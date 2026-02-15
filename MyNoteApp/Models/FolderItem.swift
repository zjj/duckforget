import Foundation
import SwiftData

@Model
final class FolderItem {
    var id: UUID
    var name: String
    var iconName: String
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \NoteItem.folder)
    var notes: [NoteItem]

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder",
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        notes: [NoteItem] = []
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.notes = notes
    }
}

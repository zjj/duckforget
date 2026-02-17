import Foundation
import SwiftData

@Model
final class NoteItem {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
    var folder: FolderItem?

    @Relationship(deleteRule: .cascade, inverse: \AttachmentItem.note)
    var attachments: [AttachmentItem]

    /// 预览：取第一行非空文本
    var preview: String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.first ?? "(仅附件)"
    }

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        folder: FolderItem? = nil,
        attachments: [AttachmentItem] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.folder = folder
        self.attachments = attachments
    }
}

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

    @Relationship(deleteRule: .cascade, inverse: \AttachmentItem.note)
    var attachments: [AttachmentItem]
    
    @Relationship(deleteRule: .nullify, inverse: \TagItem.notes)
    var tags: [TagItem]
    
    /// 存储undo/redo历史的JSON数据
    var undoRedoHistoryData: Data?
    
    /// 存储待删除的附件ID（仅在UI中隐藏，点击完成后才真正删除）
    var pendingDeletedAttachmentIDs: [UUID]? = []

    /// 预览：取前50个字符
    var preview: String {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 50 {
            return String(text.prefix(50))
        }
        return text
    }

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        attachments: [AttachmentItem] = [],
        tags: [TagItem] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.attachments = attachments
        self.tags = tags
    }
}

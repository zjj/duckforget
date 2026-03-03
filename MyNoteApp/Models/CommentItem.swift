import Foundation
import SwiftData

/// 评论模型 — 附属于 NoteItem，通过 SwiftData 持久化
@Model
final class CommentItem {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    /// 所属记录（inverse 由 NoteItem 的 @Relationship 声明）
    var note: NoteItem?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        note: NoteItem? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.note = note
    }
}

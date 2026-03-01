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

    /// 搜索索引字段：content + 所有附件 OCR 文本，以换行符拼接，每次保存时重建。
    /// 使用非可选 String 以确保 SwiftData #Predicate 能正确生成 SQL。
    var forSearch: String = ""

    /// 预览：取首个有效行的前50字符，剥离 Markdown 格式符号
    var preview: String {
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            // 跳过代码块围栏和纯分割线
            if s.hasPrefix("```") || s.hasPrefix("~~~") { continue }
            if s.allSatisfy({ $0 == "-" || $0 == "_" || $0 == "*" || $0 == " " }) { continue }

            // 去掉块级前缀
            s = s.replacingOccurrences(of: "^#{1,6} ",           with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^[\\-\\*\\+] \\[[ xX]\\] ", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^[\\-\\*\\+] ",      with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^\\d+\\. ",          with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^> ",                with: "", options: .regularExpression)

            // 去掉行内格式符号
            s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",  with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*(.+?)\\*",         with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "~~(.+?)~~",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "`([^`]+)`",           with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "",   options: .regularExpression)
            s = s.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)",with: "$1", options: .regularExpression)
            s = s.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            return s.count > 50 ? String(s.prefix(50)) : s
        }
        // 回退：原始前50字符
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.count > 50 ? String(raw.prefix(50)) : raw
    }

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        attachments: [AttachmentItem] = [],
        tags: [TagItem] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.attachments = attachments
        self.tags = tags
    }
}

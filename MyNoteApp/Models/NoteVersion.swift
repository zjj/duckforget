import Foundation
import SwiftData

// MARK: - AttachmentSnapshot

/// 附件元数据快照 — 版本保存时一并记录，用于版本详情展示和物理文件保护
struct AttachmentSnapshot: Codable, Identifiable {
    var id: UUID
    var type: AttachmentType
    var fileName: String
    var thumbnailFileName: String?

    /// 从快照列表中提取去重后的类型图标名称（用于行内小图标展示）
    static func dedupedTypes(from snapshots: [AttachmentSnapshot]) -> [String] {
        var seen = Set<String>()
        return snapshots.compactMap { snap -> String? in
            let icon = snap.type.iconName
            return seen.insert(icon).inserted ? icon : nil
        }
    }
}

// MARK: - NoteVersion

/// 笔记历史版本快照 — 每次用户完成编辑时自动保存一份内容副本
@Model
final class NoteVersion {
    var id: UUID
    /// 关联的笔记 ID（通过 UUID 软关联，避免级联删除复杂性）
    var noteID: UUID
    /// 版本内容快照
    var content: String
    /// 保存时间
    var savedAt: Date
    /// 附件快照列表（JSON 序列化），用于版本详情展示和物理文件保护
    var attachmentSnapshotsData: Data?

    /// 解码后的附件快照（只读计算属性，SwiftData 不持久化此属性）
    var attachmentSnapshots: [AttachmentSnapshot] {
        guard let data = attachmentSnapshotsData else { return [] }
        return (try? JSONDecoder().decode([AttachmentSnapshot].self, from: data)) ?? []
    }

    init(noteID: UUID, content: String, attachmentSnapshots: [AttachmentSnapshot] = [], savedAt: Date = Date()) {
        self.id = UUID()
        self.noteID = noteID
        self.content = content
        self.savedAt = savedAt
        self.attachmentSnapshotsData = attachmentSnapshots.isEmpty
            ? nil
            : (try? JSONEncoder().encode(attachmentSnapshots))
    }

    /// 内容预览：取首个有效行的前 50 字符，剥离 Markdown 格式符号
    var preview: String {
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if s.hasPrefix("```") || s.hasPrefix("~~~") { continue }
            if s.allSatisfy({ $0 == "-" || $0 == "_" || $0 == "*" || $0 == " " }) { continue }

            s = s.replacingOccurrences(of: "^#{1,6} ",            with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^[\\-\\*\\+] \\[[ xX]\\] ", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^[\\-\\*\\+] ",       with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^\\d+\\. ",           with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "^> ",                 with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",   with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\*(.+?)\\*",          with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "~~(.+?)~~",            with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "`([^`]+)`",            with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)",  with: "",   options: .regularExpression)
            s = s.replacingOccurrences(of: "\\[(.+?)\\]\\(.*?\\)", with: "$1", options: .regularExpression)
            s = s.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            return s.count > 50 ? String(s.prefix(50)) : s
        }
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.count > 50 ? String(raw.prefix(50)) : raw
    }
}

import CoreSpotlight
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 记录数据管理 - 负责所有记录和附件的CRUD及持久化（SwiftData）
@Observable
class NoteStore {
    let modelContext: ModelContext

    private let attachmentsDirName = "AttachmentFiles"

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var attachmentsDirectory: URL {
        documentsDirectory.appendingPathComponent(attachmentsDirName)
    }

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        createAttachmentsDirectoryIfNeeded()
        cleanupExpiredTrash()
    }

    // MARK: - Tag CRUD

    /// 创建标签
    @discardableResult
    func createTag(name: String) -> TagItem {
        let tag = TagItem(name: name)
        modelContext.insert(tag)
        try? modelContext.save()
        return tag
    }

    /// 重命名标签
    func renameTag(_ tag: TagItem, to newName: String) {
        tag.name = newName
        try? modelContext.save()
    }

    /// 删除标签（解除所有记录的关联，不删除记录）
    func deleteTag(_ tag: TagItem) {
        // 解除所有记录的关联
        for note in tag.notes {
            note.tags.removeAll { $0.id == tag.id }
        }
        modelContext.delete(tag)
        try? modelContext.save()
    }

    /// 获取所有标签
    func fetchTags() -> [TagItem] {
        let descriptor = FetchDescriptor<TagItem>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 为记录添加标签
    func addTag(_ tag: TagItem, to note: NoteItem) {
        if !note.tags.contains(where: { $0.id == tag.id }) {
            note.tags.append(tag)
            note.updatedAt = Date()
            try? modelContext.save()
        }
    }

    /// 从记录移除标签
    func removeTag(_ tag: TagItem, from note: NoteItem) {
        note.tags.removeAll { $0.id == tag.id }
        note.updatedAt = Date()
        try? modelContext.save()
    }
    
    /// 设置记录的标签（替换所有标签）
    func setTags(_ tags: [TagItem], for note: NoteItem) {
        note.tags = tags
        note.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Note CRUD

    /// 创建新记录
    @discardableResult
    func createNote(withTags tags: [TagItem] = []) -> NoteItem {
        let note = NoteItem(tags: tags)
        modelContext.insert(note)
        try? modelContext.save()
        // 新创建的笔记通常是空的，不立即索引
        // 当用户输入内容并保存时，updateNote 会触发索引
        return note
    }

    /// 更新记录（标记更新时间并保存）
    func updateNote(_ note: NoteItem) {
        note.updatedAt = Date()
        try? modelContext.save()
        indexNoteInSpotlight(note)
    }

    /// 软删除记录（移到"最近删除"）
    func softDeleteNote(_ note: NoteItem) {
        note.isDeleted = true
        note.deletedAt = Date()
        try? modelContext.save()
        deindexNoteFromSpotlight(note)
    }

    /// 恢复已删除记录
    func restoreNote(_ note: NoteItem) {
        note.isDeleted = false
        note.deletedAt = nil
        note.updatedAt = Date()
        try? modelContext.save()
        indexNoteInSpotlight(note)
    }

    /// 永久删除记录及其所有附件文件
    func permanentlyDeleteNote(_ note: NoteItem) {
        for attachment in note.attachments {
            removeAttachmentFile(attachment)
        }
        deindexNoteFromSpotlight(note)
        modelContext.delete(note)
        try? modelContext.save()
    }

    /// 清空回收站
    func emptyTrash() {
        let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.isDeleted == true })
        guard let trashed = try? modelContext.fetch(descriptor) else { return }
        for note in trashed {
            permanentlyDeleteNote(note)
        }
    }

    /// 清理超过配置天数的回收站记录
    func cleanupExpiredTrash() {
        let retentionDays = AppSettings.shared.trashRetentionDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate {
                $0.isDeleted == true && $0.deletedAt != nil
            })
        guard let trashed = try? modelContext.fetch(descriptor) else { return }
        for note in trashed {
            if let deletedAt = note.deletedAt, deletedAt < cutoff {
                permanentlyDeleteNote(note)
            }
        }
    }

    /// 获取回收站中的记录
    func fetchTrashedNotes() -> [NoteItem] {
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { $0.isDeleted == true },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 添加附件（无缩略图）
    @discardableResult
    func addAttachment(to note: NoteItem, type: AttachmentType, data: Data, fileExtension: String, shouldSave: Bool = true)
        -> AttachmentItem?
    {
        return addAttachmentWithThumbnail(
            to: note, type: type, data: data, thumbnailData: nil, fileExtension: fileExtension, shouldSave: shouldSave)
    }

    /// 添加附件（含缩略图）
    @discardableResult
    func addAttachmentWithThumbnail(
        to note: NoteItem,
        type: AttachmentType,
        data: Data,
        thumbnailData: Data?,
        fileExtension: String,
        shouldSave: Bool = true
    ) -> AttachmentItem? {
        let fileID = UUID().uuidString
        let fileName = "\(fileID).\(fileExtension)"
        var thumbnailFileName: String? = nil

        if let thumbnailData = thumbnailData {
            thumbnailFileName = "\(fileID)_thumb.jpg"
            let thumbURL = attachmentsDirectory.appendingPathComponent(thumbnailFileName!)
            try? thumbnailData.write(to: thumbURL)
        }

        let fileURL = attachmentsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
        } catch {
            print("❌ 保存附件失败: \(error)")
            return nil
        }

        let attachment = AttachmentItem(
            type: type,
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            createdAt: Date()
        )

        attachment.note = note
        note.attachments.append(attachment)
        note.updatedAt = Date()

        modelContext.insert(attachment)
        if shouldSave {
            try? modelContext.save()
        }
        return attachment
    }

    /// 删除附件
    func deleteAttachment(_ attachment: AttachmentItem, shouldSave: Bool = true) {
        // 如果是自动保存模式，则立即删除物理文件
        if shouldSave {
            removeAttachmentFile(attachment)
        }

        if let note = attachment.note {
            note.updatedAt = Date()
        }

        modelContext.delete(attachment)
        
        if shouldSave {
            try? modelContext.save()
        }
    }

    /// 获取附件文件URL
    func attachmentURL(for attachment: AttachmentItem) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.fileName)
    }

    /// 获取缩略图URL
    func thumbnailURL(for attachment: AttachmentItem) -> URL? {
        guard let thumbName = attachment.thumbnailFileName else { return nil }
        return attachmentsDirectory.appendingPathComponent(thumbName)
    }

    /// 获取记录的所有附件（按创建时间排序）
    func getAttachments(for note: NoteItem) -> [AttachmentItem] {
        note.attachments.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Export

    /// 导出为纯文本
    func exportAsText(_ note: NoteItem) -> String {
        var result = note.content
        if !note.attachments.isEmpty {
            result += "\n\n---\n附件: \(note.attachments.count) 个"
        }
        return result
    }

    /// 导出为 PDF Data
    func exportAsPDF(_ note: NoteItem) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { ctx in
            ctx.beginPage()

            // 标题
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
            ]
            let titleStr = note.preview as NSString
            let titleRect = CGRect(x: margin, y: margin, width: contentWidth, height: 40)
            titleStr.draw(in: titleRect, withAttributes: titleAttr)

            // 日期
            let dateFont = UIFont.systemFont(ofSize: 12)
            let dateAttr: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.gray,
            ]
            let dateStr = note.updatedAt.formattedFull as NSString
            let dateRect = CGRect(x: margin, y: margin + 45, width: contentWidth, height: 20)
            dateStr.draw(in: dateRect, withAttributes: dateAttr)

            // 正文
            let bodyFont = UIFont.systemFont(ofSize: 14)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraphStyle,
            ]
            let bodyStr = note.content as NSString
            let bodyMaxRect = CGRect(
                x: margin, y: margin + 75, width: contentWidth, height: pageHeight - margin * 2 - 75
            )
            bodyStr.draw(in: bodyMaxRect, withAttributes: bodyAttr)
        }
    }

    // MARK: - Spotlight

    func indexNoteInSpotlight(_ note: NoteItem) {
        // 只索引非空的笔记
        guard !note.content.isEmpty || !note.attachments.isEmpty else {
            return
        }
        
        let attributeSet = CSSearchableItemAttributeSet(contentType: UTType.text)
        
        // 标题和显示名称
        attributeSet.title = note.preview
        attributeSet.displayName = note.preview
        
        // 内容 - 这是关键！
        attributeSet.textContent = note.content
        attributeSet.contentDescription = note.content
        
        // 日期
        attributeSet.contentModificationDate = note.updatedAt
        attributeSet.contentCreationDate = note.createdAt
        
        // 标签作为关键词
        if !note.tags.isEmpty {
            attributeSet.keywords = note.tags.map { $0.name }
        }

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: "net.zhongjj.MyNoteApp.notes",
            attributeSet: attributeSet
        )
        item.expirationDate = Date.distantFuture

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in
            // 静默索引，不输出日志
        }
    }

    func deindexNoteFromSpotlight(_ note: NoteItem) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [note.id.uuidString]
        ) { _ in }
    }

    /// 索引所有非删除的记录到 Spotlight
    func reindexAllNotes() {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
        
        let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.isDeleted == false })
        guard let notes = try? modelContext.fetch(descriptor) else { return }
        
        for note in notes {
            indexNoteInSpotlight(note)
        }
    }

    // MARK: - Private Helpers

    private func removeAttachmentFile(_ attachment: AttachmentItem) {
        let fileURL = attachmentsDirectory.appendingPathComponent(attachment.fileName)
        try? FileManager.default.removeItem(at: fileURL)

        if let thumbName = attachment.thumbnailFileName {
            let thumbURL = attachmentsDirectory.appendingPathComponent(thumbName)
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }

    private func createAttachmentsDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: attachmentsDirectory.path) {
            try? fm.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
    }
}

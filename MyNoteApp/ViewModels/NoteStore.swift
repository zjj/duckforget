import CoreSpotlight
import SwiftData
import SwiftUI
import UIKit

/// 备忘录数据管理 - 负责所有备忘录和附件的CRUD及持久化（SwiftData）
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

    // MARK: - Folder CRUD

    /// 创建文件夹
    @discardableResult
    func createFolder(name: String, iconName: String = "folder") -> FolderItem {
        let folder = FolderItem(name: name, iconName: iconName)
        modelContext.insert(folder)
        try? modelContext.save()
        return folder
    }

    /// 重命名文件夹
    func renameFolder(_ folder: FolderItem, to newName: String) {
        folder.name = newName
        try? modelContext.save()
    }

    /// 删除文件夹（其中的备忘录移到根级）
    func deleteFolder(_ folder: FolderItem) {
        for note in folder.notes {
            note.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
    }

    /// 获取所有文件夹
    func fetchFolders() -> [FolderItem] {
        let descriptor = FetchDescriptor<FolderItem>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 移动备忘录到文件夹
    func moveNote(_ note: NoteItem, to folder: FolderItem?) {
        note.folder = folder
        note.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Note CRUD

    /// 创建新备忘录
    @discardableResult
    func createNote(in folder: FolderItem? = nil) -> NoteItem {
        let note = NoteItem(folder: folder)
        modelContext.insert(note)
        try? modelContext.save()
        return note
    }

    /// 更新备忘录（标记更新时间并保存）
    func updateNote(_ note: NoteItem) {
        note.updatedAt = Date()
        try? modelContext.save()
        indexNoteInSpotlight(note)
    }

    /// 软删除备忘录（移到"最近删除"）
    func softDeleteNote(_ note: NoteItem) {
        note.isDeleted = true
        note.deletedAt = Date()
        note.folder = nil
        try? modelContext.save()
        deindexNoteFromSpotlight(note)
    }

    /// 恢复已删除备忘录
    func restoreNote(_ note: NoteItem, to folder: FolderItem? = nil) {
        note.isDeleted = false
        note.deletedAt = nil
        note.folder = folder
        note.updatedAt = Date()
        try? modelContext.save()
        indexNoteInSpotlight(note)
    }

    /// 永久删除备忘录及其所有附件文件
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

    /// 清理超过 30 天的回收站备忘录
    func cleanupExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
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

    /// 获取回收站中的备忘录
    func fetchTrashedNotes() -> [NoteItem] {
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { $0.isDeleted == true },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Attachment Management

    /// 添加附件（无缩略图）
    @discardableResult
    func addAttachment(to note: NoteItem, type: AttachmentType, data: Data, fileExtension: String)
        -> AttachmentItem?
    {
        return addAttachmentWithThumbnail(
            to: note, type: type, data: data, thumbnailData: nil, fileExtension: fileExtension)
    }

    /// 添加附件（含缩略图）
    @discardableResult
    func addAttachmentWithThumbnail(
        to note: NoteItem,
        type: AttachmentType,
        data: Data,
        thumbnailData: Data?,
        fileExtension: String
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
        try? modelContext.save()
        return attachment
    }

    /// 删除附件
    func deleteAttachment(_ attachment: AttachmentItem) {
        removeAttachmentFile(attachment)

        if let note = attachment.note {
            note.updatedAt = Date()
        }

        modelContext.delete(attachment)
        try? modelContext.save()
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

    /// 获取备忘录的所有附件（按创建时间排序）
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
            let titleStr = note.title as NSString
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
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = note.title
        attributeSet.contentDescription = note.preview
        attributeSet.contentModificationDate = note.updatedAt

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: "com.mynoteapp.notes",
            attributeSet: attributeSet
        )
        item.expirationDate = Date.distantFuture

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                print("❌ Spotlight 索引失败: \(error)")
            }
        }
    }

    func deindexNoteFromSpotlight(_ note: NoteItem) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [note.id.uuidString]
        ) { error in
            if let error = error {
                print("❌ Spotlight 移除失败: \(error)")
            }
        }
    }

    /// 索引所有非删除的备忘录到 Spotlight
    func reindexAllNotes() {
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

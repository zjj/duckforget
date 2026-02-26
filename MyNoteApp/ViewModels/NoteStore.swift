import CoreSpotlight
import NaturalLanguage
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
        cleanupEmptyNotes()
    }

    // MARK: - Tag CRUD

    /// 创建标签
    @discardableResult
    func createTag(name: String) -> TagItem {
        let tag = TagItem(name: name)
        modelContext.insert(tag)
        saveContext()
        return tag
    }

    /// 重命名标签
    func renameTag(_ tag: TagItem, to newName: String) {
        tag.name = newName
        saveContext()
    }

    /// 删除标签（解除所有记录的关联，不删除记录）
    func deleteTag(_ tag: TagItem) {
        // 解除所有记录的关联
        for note in tag.notes {
            note.tags.removeAll { $0.id == tag.id }
        }
        modelContext.delete(tag)
        saveContext()
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
            saveContext()
        }
    }

    /// 从记录移除标签
    func removeTag(_ tag: TagItem, from note: NoteItem) {
        note.tags.removeAll { $0.id == tag.id }
        note.updatedAt = Date()
        saveContext()
    }
    
    /// 设置记录的标签（替换所有标签）
    func setTags(_ tags: [TagItem], for note: NoteItem) {
        note.tags = tags
        note.updatedAt = Date()
        saveContext()
    }

    // MARK: - Note CRUD

    /// 创建新记录
    @discardableResult
    func createNote(withTags tags: [TagItem] = []) -> NoteItem {
        let note = NoteItem(tags: tags)
        modelContext.insert(note)
        saveContext()
        // 新创建的笔记通常是空的，不立即索引
        // 当用户输入内容并保存时，updateNote 会触发索引
        return note
    }

    /// 更新记录（标记更新时间并保存）
    func updateNote(_ note: NoteItem) {
        note.updatedAt = Date()
        saveContext()
        indexNoteInSpotlight(note)
    }

    /// 软删除记录（移到"最近删除"）
    func softDeleteNote(_ note: NoteItem) {
        note.isDeleted = true
        note.deletedAt = Date()
        saveContext()
        deindexNoteFromSpotlight(note)
    }

    /// 恢复已删除记录
    func restoreNote(_ note: NoteItem) {
        note.isDeleted = false
        note.deletedAt = nil
        note.updatedAt = Date()
        saveContext()
        indexNoteInSpotlight(note)
    }

    /// 永久删除记录及其所有附件文件
    func permanentlyDeleteNote(_ note: NoteItem) {
        let attachmentsToDelete = note.attachments
        deindexNoteFromSpotlight(note)
        modelContext.delete(note)
        // 先保存数据库，成功后再清理物理文件（防止数据库保存失败导致文件丢失）
        saveContext {
            attachmentsToDelete.forEach { self.removeAttachmentFile($0) }
        }
    }

    /// 清空废纸篓（批量删除，仅一次 modelContext.save()）
    func emptyTrash() {
        let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.isDeleted == true })
        guard let trashed = try? modelContext.fetch(descriptor), !trashed.isEmpty else { return }
        let allAttachments = trashed.flatMap { $0.attachments }
        for note in trashed {
            deindexNoteFromSpotlight(note)
            modelContext.delete(note)
        }
        saveContext {
            allAttachments.forEach { self.removeAttachmentFile($0) }
        }
    }

    /// 清理孤立的空笔记（无内容、无附件、未删除的笔记）
    /// 用于处理从小组件创建但未输入内容、且 NoteView.onDisappear 未正常触发的情况
    func cleanupEmptyNotes() {
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { note in
                note.isDeleted == false
            }
        )
        guard let notes = try? modelContext.fetch(descriptor) else { return }
        for note in notes {
            let contentEmpty = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let noAttachments = note.attachments.isEmpty
            if contentEmpty && noAttachments {
                modelContext.delete(note)
            }
        }
        saveContext()
    }

    /// 清理超过配置天数的废纸篓记录
    func cleanupExpiredTrash() {
        let retentionDays = AppSettings.shared.trashRetentionDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        // 将日期条件下推到 SwiftData Predicate，让数据库层过滤，避免全量加载再 Swift 筛选
        let descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { note in
                note.isDeleted == true && note.deletedAt != nil && note.deletedAt! < cutoff
            })
        guard let expired = try? modelContext.fetch(descriptor) else { return }
        for note in expired {
            permanentlyDeleteNote(note)
        }
    }

    /// 获取废纸篓中的记录
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
            do {
                try thumbnailData.write(to: thumbURL)
            } catch {
                print("❌ 保存缩略图失败: \(error)")
                return nil
            }
        }

        let fileURL = attachmentsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
        } catch {
            print("❌ 保存附件数据失败: \(error)")
            // 回退：如果缩略图已写入但主文件写入失败，则尝试清理缩略图
            if let thumbName = thumbnailFileName {
                let thumbURL = attachmentsDirectory.appendingPathComponent(thumbName)
                try? FileManager.default.removeItem(at: thumbURL)
            }
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
            saveContext()
        }
        return attachment
    }

    /// 删除附件
    func deleteAttachment(_ attachment: AttachmentItem, shouldSave: Bool = true) {
        if let note = attachment.note {
            note.updatedAt = Date()
        }
        modelContext.delete(attachment)
        if shouldSave {
            // 先保存数据库，成功后再删除物理文件（防止破损链接）
            saveContext { self.removeAttachmentFile(attachment) }
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


    // MARK: - Spotlight

    func indexNoteInSpotlight(_ note: NoteItem) {
        // 1. 提前捕获元数据，避免在回调中跨线程访问 SwiftData 对象
        let noteID = note.id.uuidString
        let noteTitle = note.preview
        let noteContent = note.content
        let noteUpdatedAt = note.updatedAt
        let noteCreatedAt = note.createdAt
        let noteTags = note.tags.map { $0.name }

        // 只索引非空的笔记
        guard !noteContent.isEmpty || !note.attachments.isEmpty else { return }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // 标题和显示名称
        attributeSet.title = noteTitle
        attributeSet.displayName = noteTitle
        attributeSet.contentDescription = noteContent
        attributeSet.textContent = noteContent // 恢复 textContent 以支持系统原生全文索引作为兜底

        // 日期
        attributeSet.contentModificationDate = noteUpdatedAt
        attributeSet.contentCreationDate = noteCreatedAt

        // 分词增强：提取正文中的关键词
        let bodyTokens = tokenize(noteContent)
        var keywords = noteTags
        var seen = Set<String>(keywords)
        for token in bodyTokens {
            if seen.insert(token).inserted {
                keywords.append(token)
            }
        }
        attributeSet.keywords = keywords

        let item = CSSearchableItem(
            uniqueIdentifier: noteID,
            domainIdentifier: "com.duckforget.MyNoteApp.notes",
            attributeSet: attributeSet
        )
        item.expirationDate = Date.distantFuture

        CSSearchableIndex.default().indexSearchableItems([item]) { _ in
        }
    }

    func deindexNoteFromSpotlight(_ note: NoteItem) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [note.id.uuidString]
        ) { _ in
        }
    }

    // MARK: - NL Tokenization Helper

    /// 使用 NLTokenizer 对文本进行分词，返回去重后的词元列表
    private func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese) // 设置中文分词
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if !token.isEmpty && token.count > 1 { // 过滤掉单字符词元
                tokens.append(token)
            }
            return true
        }
        // 去重，保留顺序
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }

    /// 索引所有非删除的记录到 Spotlight
    //func reindexAllNotes() {
    //    CSSearchableIndex.default().deleteAllSearchableItems { _ in }
    //    
    //    let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.isDeleted == false })
    //    guard let notes = try? modelContext.fetch(descriptor) else { return }
    //    
    //    for note in notes {
    //        indexNoteInSpotlight(note)
    //    }
    //}

    // MARK: - Persistence

    /// 保存 ModelContext。保存成功后执行 onSuccess 回调（用于依赖保存结果的后续操作，例如删除物理文件）。
    /// Debug 下通过 assertionFailure 暴露错误；Release 下打印日志静默处理，避免数据静默丢失。
    private func saveContext(onSuccess: (() -> Void)? = nil) {
        do {
            try modelContext.save()
            onSuccess?()
        } catch {
            print("❌ [NoteStore] modelContext.save() 失败: \(error)")
            assertionFailure("[NoteStore] modelContext.save() 失败: \(error)")
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

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

    /// 每次 updateNote 调用时自增，供 UI 组件监听并刷新列表
    private(set) var contentRevision: Int = 0

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 附件目录（内部可访问，供 MarkdownRenderView / ExportService 解析相对路径）
    var attachmentsDirectory: URL {
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
    /// 注意：仅将记录插入 ModelContext（内存），不立即持久化。
    /// 首次有实际内容时（updateNote / saveContentInEditMode）才会触发真正的 save。
    /// 这样若用户立即返回、未输入任何内容，数据库中不会留下空记录。
    @discardableResult
    func createNote(withTags tags: [TagItem] = []) -> NoteItem {
        let note = NoteItem(tags: tags)
        modelContext.insert(note)
        return note
    }

    /// 更新记录（标记更新时间并保存）
    func updateNote(_ note: NoteItem) {
        note.updatedAt = Date()
        // 重建搜索索引：content + 所有附件 OCR 文本 + 拼音
        let ocrParts = note.attachments.compactMap { $0.recognitionMeta }.filter { !$0.isEmpty }
        let base = ([note.content] + ocrParts).joined(separator: "\n")
        let pinyin = PinyinConverter.pinyinForSearch(base)
        note.forSearch = pinyin.isEmpty ? base : base + "\n" + pinyin
        contentRevision &+= 1
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
        // 不更新 updatedAt：恢复操作不是内容修改，保留上次真实编辑时间
        saveContext()
        indexNoteInSpotlight(note)
    }

    /// 永久删除记录及其所有附件文件
    func permanentlyDeleteNote(_ note: NoteItem) {
        let noteID = note.id
        // 提前捕获文件名，避免 delete 后访问已释放的对象
        let attachmentFiles = note.attachments.map {
            (fileName: $0.fileName, thumbName: $0.thumbnailFileName)
        }
        deindexNoteFromSpotlight(note)
        // 先删除所有历史版本（删除后即可安全删除物理文件，无需版本引用检查）
        for v in fetchVersions(for: noteID) { modelContext.delete(v) }
        modelContext.delete(note)
        // 先保存数据库，成功后再清理物理文件（防止数据库保存失败导致文件丢失）
        saveContext {
            attachmentFiles.forEach {
                self.deleteAttachmentFiles(fileName: $0.fileName, thumbnailFileName: $0.thumbName)
            }
        }
    }

    /// 清空废纸篓（批量删除，仅一次 modelContext.save()）
    func emptyTrash() {
        let descriptor = FetchDescriptor<NoteItem>(predicate: #Predicate { $0.isDeleted == true })
        guard let trashed = try? modelContext.fetch(descriptor), !trashed.isEmpty else { return }
        let allAttachmentFiles = trashed.flatMap { note in
            note.attachments.map { (fileName: $0.fileName, thumbName: $0.thumbnailFileName) }
        }
        for note in trashed {
            deindexNoteFromSpotlight(note)
            // 先删除历史版本，确保文件可以安全删除
            for v in fetchVersions(for: note.id) { modelContext.delete(v) }
            modelContext.delete(note)
        }
        saveContext {
            allAttachmentFiles.forEach {
                self.deleteAttachmentFiles(fileName: $0.fileName, thumbnailFileName: $0.thumbName)
            }
        }
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

    // MARK: - Comment CRUD

    /// 为记录添加一条评论
    @discardableResult
    func addComment(to note: NoteItem, content: String) -> CommentItem {
        let comment = CommentItem(content: content, note: note)
        modelContext.insert(comment)
        note.comments.append(comment)
        saveContext()
        return comment
    }

    /// 更新评论内容
    func updateComment(_ comment: CommentItem, content: String) {
        comment.content = content
        comment.updatedAt = Date()
        saveContext()
    }

    /// 删除评论
    func deleteComment(_ comment: CommentItem) {
        if let note = comment.note {
            note.comments.removeAll { $0.id == comment.id }
        }
        modelContext.delete(comment)
        saveContext()
    }

    /// 获取记录的所有评论（按创建时间倒序）
    func getComments(for note: NoteItem) -> [CommentItem] {
        note.comments.sorted { $0.createdAt > $1.createdAt }
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
        let fileName = attachment.fileName
        let thumbName = attachment.thumbnailFileName
        let noteID = attachment.note?.id
        if let note = attachment.note {
            note.updatedAt = Date()
        }
        modelContext.delete(attachment)
        if shouldSave {
            // 先保存数据库，成功后再删除物理文件（防止破损链接）
            saveContext {
                // 若该笔记的历史版本中仍引用此文件，则保留物理文件
                if let noteID, self.isAttachmentFileReferencedByVersions(fileName: fileName, noteID: noteID) {
                    return
                }
                self.deleteAttachmentFiles(fileName: fileName, thumbnailFileName: thumbName)
            }
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
        let forSearchContent = note.forSearch
        let noteUpdatedAt = note.updatedAt
        let noteCreatedAt = note.createdAt
        let noteTags = note.tags.map { $0.name }

        // 只索引非空的笔记
        guard !forSearchContent.isEmpty || !note.attachments.isEmpty else { return }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // 标题和显示名称
        attributeSet.title = noteTitle
        attributeSet.displayName = noteTitle
        attributeSet.contentDescription = noteContent  // Spotlight 卡片展示内容，只用正文
        attributeSet.textContent = forSearchContent   // Spotlight 全文索引，包含正文 + 附件 OCR 文本

        // 日期
        attributeSet.contentModificationDate = noteUpdatedAt
        attributeSet.contentCreationDate = noteCreatedAt

        // 分词增强：提取正文中的关键词
        let bodyTokens = tokenize(forSearchContent)
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

    /// 将 OCR 结果写入附件并重建所属笔记的 forSearch 索引
    func applyRecognitionMeta(to attachment: AttachmentItem, text: String) {
        attachment.recognitionMeta = text.isEmpty ? nil : text
        if let note = attachment.note {
            let ocrParts = note.attachments.compactMap { $0.recognitionMeta }.filter { !$0.isEmpty }
            let base = ([note.content] + ocrParts).joined(separator: "\n")
            let pinyin = PinyinConverter.pinyinForSearch(base)
            note.forSearch = pinyin.isEmpty ? base : base + "\n" + pinyin
        }
        saveContext()
    }

    // MARK: - Version History

    /// 每个笔记最多保留的历史版本数
    private let maxVersionsPerNote = 50

    /// 完成编辑时以当前内容保存一份历史版本快照
    /// - 内容为空时不保存；与最新版本内容完全相同时同样跳过
    func saveVersion(for note: NoteItem) {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let noteID = note.id
        // 检查是否与最新快照内容一致，一致则跳过
        var latestDesc = FetchDescriptor<NoteVersion>(
            predicate: #Predicate { $0.noteID == noteID },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        latestDesc.fetchLimit = 1
        if let latest = try? modelContext.fetch(latestDesc).first,
           latest.content == note.content {
            return
        }

        // 捕获当前附件快照
        let snapshots = note.attachments
            .sorted { $0.createdAt < $1.createdAt }
            .map { AttachmentSnapshot(id: $0.id, type: $0.type, fileName: $0.fileName, thumbnailFileName: $0.thumbnailFileName) }

        let version = NoteVersion(noteID: noteID, content: note.content, attachmentSnapshots: snapshots)
        modelContext.insert(version)

        // 超出上限时删除最旧的版本（保持总量在 maxVersionsPerNote 以内）
        let allDesc = FetchDescriptor<NoteVersion>(
            predicate: #Predicate { $0.noteID == noteID },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        if let all = try? modelContext.fetch(allDesc), all.count > maxVersionsPerNote {
            for old in all.dropFirst(maxVersionsPerNote) {
                modelContext.delete(old)
            }
        }

        saveContext()
    }

    /// 获取指定笔记的所有历史版本（按保存时间倒序）
    func fetchVersions(for noteID: UUID) -> [NoteVersion] {
        let descriptor = FetchDescriptor<NoteVersion>(
            predicate: #Predicate { $0.noteID == noteID },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 删除单条历史版本
    func deleteVersion(_ version: NoteVersion) {
        modelContext.delete(version)
        saveContext()
    }

    /// 清空某笔记的全部历史版本
    func deleteAllVersions(for noteID: UUID) {
        let versions = fetchVersions(for: noteID)
        for v in versions { modelContext.delete(v) }
        if !versions.isEmpty { saveContext() }
    }

    /// 将笔记内容和附件完整恢复到指定历史版本
    ///
    /// - 恢复文本内容
    /// - 当前附件中不在版本快照里的 → 从 note 移除（物理文件若被其他版本引用则保留）
    /// - 版本快照中存在但 note 里已删除的 → 重建 AttachmentItem（物理文件被版本保护，已在磁盘上）
    func restoreVersion(_ version: NoteVersion, to note: NoteItem) {
        let snapshots = version.attachmentSnapshots
        let snapshotIDs = Set(snapshots.map { $0.id })
        let current = getAttachments(for: note)
        let currentIDs = Set(current.map { $0.id })
        let noteID = note.id

        // 1. 移除当前多余的附件
        var filesToMaybeDelete: [(fileName: String, thumbName: String?)] = []
        for att in current where !snapshotIDs.contains(att.id) {
            filesToMaybeDelete.append((att.fileName, att.thumbnailFileName))
            modelContext.delete(att)
        }

        // 2. 重建版本快照里有、但当前已不存在的附件
        for snap in snapshots where !currentIDs.contains(snap.id) {
            let fileURL = attachmentsDirectory.appendingPathComponent(snap.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let att = AttachmentItem(
                id: snap.id,
                type: snap.type,
                fileName: snap.fileName,
                thumbnailFileName: snap.thumbnailFileName
            )
            modelContext.insert(att)
            note.attachments.append(att)
        }

        // 3. 恢复文本并持久化
        note.content = version.content
        note.pendingDeletedAttachmentIDs = []
        updateNote(note)
        saveVersion(for: note)

        // 4. 清理已无任何版本引用的孤立物理文件
        for file in filesToMaybeDelete
        where !isAttachmentFileReferencedByVersions(fileName: file.fileName, noteID: noteID) {
            deleteAttachmentFiles(fileName: file.fileName, thumbnailFileName: file.thumbName)
        }
    }

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

    /// 直接删除附件物理文件（无版本安全检查，仅在已确认无版本引用时调用）
    private func deleteAttachmentFiles(fileName: String, thumbnailFileName: String?) {
        let fileURL = attachmentsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)

        if let thumbName = thumbnailFileName {
            let thumbURL = attachmentsDirectory.appendingPathComponent(thumbName)
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }

    /// 检查附件文件是否仍被该笔记的某个历史版本引用
    /// （内容中的 attachment:// 链接，或附件快照列表）
    private func isAttachmentFileReferencedByVersions(fileName: String, noteID: UUID) -> Bool {
        let versions = fetchVersions(for: noteID)
        for version in versions {
            if version.content.contains("attachment://\(fileName)") { return true }
            if version.attachmentSnapshots.contains(where: {
                $0.fileName == fileName || $0.thumbnailFileName == fileName
            }) { return true }
        }
        return false
    }

    private func createAttachmentsDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: attachmentsDirectory.path) {
            try? fm.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
    }
}

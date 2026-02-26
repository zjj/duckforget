import SwiftUI
import SwiftData

// MARK: - 编辑操作

extension NoteView {

    /// 进入编辑模式
    func enterEditMode() {
        isEditMode = true
        showExpandedFormatBar = false
        // isEditMode 变为 true 后，MarkdownTextView 首次进入视图层，makeUIView 完成后
        // onCoordinatorReady 会触发。若协调器已存在则可直接延迟较短时间聚焦。
        if let coord = markdownCoordinator {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                coord.focus()
            }
        } else {
            shouldAutoFocus = true
        }
    }
    
    /// 退出编辑模式（完成编辑）
    func exitEditMode() {
        showExpandedFormatBar = false
        // 取消延迟保存任务
        saveTask?.cancel()
        
        // 执行实际的附件删除（只在完成时删除）
        for attachmentID in deletedAttachmentIDs {
            if let attachment = noteStore.getAttachments(for: note).first(where: { $0.id == attachmentID }) {
                noteStore.deleteAttachment(attachment, shouldSave: true)
            }
        }
        deletedAttachmentIDs.removeAll()
        
        // 最终更新内容共并持久化
        note.content = content
        note.pendingDeletedAttachmentIDs = []
        
        // 清空undo/redo历史（完成编辑后清空）
        undoRedoManager.clear()
        note.undoRedoHistoryData = nil
        
        // 统一提交保存（updateNote 内部已调用 saveContext）
        noteStore.updateNote(note)
        
        // 取消键盘焦点
        markdownCoordinator?.blur()
        
        // 震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 切换到预览模式
        isEditMode = false
    }
    
    /// 执行撤销操作
    func performUndo() {
        guard let action = undoRedoManager.undo() else { return }
        
        // 标记正在执行undo操作，避免触发onChange记录
        isPerformingUndoRedo = true
        
        switch action {
        case .textChange(let previousText, _):
            // 恢复之前的文本
            content = previousText
            // 更新previousContent以保持同步
            previousContent = previousText
            
        case .attachmentAdded(let attachmentID):
            // 撤销添加 = 删除附件（添加到删除列表）
            deletedAttachmentIDs.insert(attachmentID)
            
        case .attachmentDeleted(let attachmentID):
            // 撤销删除 = 恢复附件（从删除列表移除）
            deletedAttachmentIDs.remove(attachmentID)
        }
        
        // 清除标记
        isPerformingUndoRedo = false
        
        // 实时保存
        saveContentInEditMode()
    }
    
    /// 执行重做操作
    func performRedo() {
        guard let action = undoRedoManager.redo() else { return }
        
        // 标记正在执行redo操作，避免触发onChange记录
        isPerformingUndoRedo = true
        
        switch action {
        case .textChange(_, let newText):
            // 应用新文本
            content = newText
            // 更新previousContent以保持同步
            previousContent = newText
            
        case .attachmentAdded(let attachmentID):
            // 重做添加 = 恢复附件（从删除列表移除）
            deletedAttachmentIDs.remove(attachmentID)
            
        case .attachmentDeleted(let attachmentID):
            // 重做删除 = 删除附件（添加到删除列表）
            deletedAttachmentIDs.insert(attachmentID)
        }
        
        // 清除标记
        isPerformingUndoRedo = false
        
        // 实时保存
        saveContentInEditMode()
    }
    
    /// 编辑模式下的实时保存
    func saveContentInEditMode() {
        // 更新笔记内容
        note.content = content
        
        // 注意：不在编辑模式时删除附件，只是在 UI 中隐藏
        // 实际删除只在点击"完成"或退出时进行
        
        // 保存待删除的附件ID列表
        note.pendingDeletedAttachmentIDs = Array(deletedAttachmentIDs)
        
        // 保存undo/redo历史到数据库
        note.undoRedoHistoryData = undoRedoManager.serializeHistory()
        
        // 保存到数据库（updateNote 内部已调用 saveContext）
        noteStore.updateNote(note)
        
        // 更新基准状态
        initialContent = note.content
        initialAttachmentCount = currentAttachments.count
        // 注意：不清空 deletedAttachmentIDs，保持删除状态直到完成编辑
        initialTagIDs = Set(note.tags.map { $0.id })
        wasEdited = false
    }

    // MARK: 导出

    func triggerExport(format: ExportFormat) {
        isExporting = true
        let service = ExportService(noteStore: noteStore)
        let capturedNote = note
        Task {
            do {
                let url = try service.export(note: capturedNote, format: format)
                isExporting = false
                exportFileURL = url
                showShareSheet = true
            } catch {
                isExporting = false
                exportError = error.localizedDescription
                showExportError = true
            }
        }
    }

    func loadContent() {
        guard !hasLoaded else { return }
        content = note.content
        previousContent = note.content // 初始化 previousContent
        initialContent = note.content // 保存初始内容
        initialAttachmentCount = currentAttachments.count // 保存初始附件数量
        
        // 载入标签状态
        initialTagIDs = Set(note.tags.map { $0.id })
        
        // 初始化附件ID集合
        previousAttachmentIDs = Set(currentAttachments.map { $0.id })
        
        // 加载待删除的附件ID列表
        deletedAttachmentIDs = Set(note.pendingDeletedAttachmentIDs ?? [])
        
        // 加载undo/redo历史（如果存在）
        if let historyData = note.undoRedoHistoryData {
            undoRedoManager.loadHistory(from: historyData)
        } else {
            // 新笔记或没有历史，清空管理器
            undoRedoManager.clear()
        }
        
        // 初始化编辑模式
        isEditMode = startInEditMode || onPublish != nil
        
        // 如果从编辑模式启动，等待协调器就绪后自动聚焦（避免计时器竞争条件）
        if isEditMode {
            shouldAutoFocus = true
        }

        hasLoaded = true
    }

    func cleanupOnExit() {
        // 如果正在删除，跳过清理（避免覆盖删除状态）
        guard !isDeleting else { return }
        
        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        
        // 取消任何待处理的保存任务
        saveTask?.cancel()
        
        // 如果笔记创建时就是空的，且退出时仍然为空（无内容、无附件），
        // 直接删除这条空笔记（例如从小组件创建但未输入任何内容）
        let wasEmptyOnLoad = initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && initialAttachmentCount == 0
        let isStillEmpty = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && currentAttachments.isEmpty
        if wasEmptyOnLoad && isStillEmpty {
            noteStore.permanentlyDeleteNote(note)
            return
        }
        
        // 最终保存（确保所有内容都持久化）
        if content != note.content {
            note.content = content
            note.updatedAt = Date()
        }
        
        // 保存编辑状态（保留undo/redo历史，下次可继续使用）
        note.pendingDeletedAttachmentIDs = Array(deletedAttachmentIDs)
        note.undoRedoHistoryData = undoRedoManager.serializeHistory()
        
        // 统一保存
        try? noteStore.modelContext.save()
    }
}

import AVFoundation
import SwiftUI
import CoreLocation
import SwiftData

/// 记录视图 - 支持预览/编辑模式切换，文字输入、语音转文字、附件管理
struct NoteView: View {
    let note: NoteItem
    var startInEditMode: Bool = false
    var onFocusChange: ((Bool) -> Void)? = nil
    var onPublish: (() -> Void)? = nil
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var toolbarSettings: ToolbarSettings

    // 编辑模式状态
    @State private var isEditMode = false
    
    // 内容状态
    @State private var content = ""
    @State private var hasLoaded = false
    @State private var isEditorFocused = false
    @State private var cursorPosition: Int = 0

    // 语音实时插入状态
    @State private var speechInsertionIndex: Int = 0
    @State private var contentBeforeSpeech: String = ""
    @State private var contentAfterSpeech: String = ""
    @State private var lastTranscriptLength: Int = 0

    // 弹出控制
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var activeScanMode: ScanMode?
    @State private var showAudioRecorder = false
    @State private var showPaintingCanvas = false
    @State private var showFilePicker = false
    @State private var showLocationPicker = false

    // 附件查看
    @State private var selectedAttachment: AttachmentItem?

    // 语音输入
    @StateObject private var speechRecognizer = SpeechRecognizer()

    // 文本视图 coordinator 引用
    @State private var textViewCoordinator: CursorTrackingTextView.Coordinator?

    // 撤销/重做管理器
    @StateObject private var undoRedoManager = UndoRedoManager()
    
    // 编辑内容追踪
    @State private var previousContent = "" // 用于记录文本变化
    @State private var saveTask: Task<Void, Never>? // 用于延迟保存
    @State private var previousAttachmentIDs: Set<UUID> = [] // 用于跟踪附件变化
    @State private var isPerformingUndoRedo = false // 标记是否正在执行撤销/重做操作
    
    // 标签管理
    @State private var showTagManagement = false

    // 富文本工具栏
    @State private var showRichTextBar = false

    // 编辑状态追踪
    @State private var wasEdited = false
    @State private var initialContent = "" // 初始内容，用于检测是否有变化
    @State private var initialAttachmentCount = 0 // 初始附件数量
    @State private var initialTagIDs: Set<UUID> = [] // 初始标签 ID 集合
    @State private var deletedAttachmentIDs: Set<UUID> = [] // 临时删除的附件 ID，用于 UI 隐藏

    // 语音输入拖拽状态
    @State private var voiceDragOffset: CGFloat = 0
    @State private var isVoiceButtonPressed = false
    @State private var shouldCancelVoiceInput = false
    
    // 删除确认
    @State private var showDeleteConfirmation = false
    
    // 删除中标记（防止 cleanupOnExit 干扰）
    @State private var isDeleting = false

    enum ScanMode: String, Identifiable {
        case textExtraction // Renamed from text
        case documentScan   // Renamed from document
        var id: String { rawValue }
    }

    /// 富文本格式类型
    enum TextFormat {
        case bold, italic
    }

    // MARK: - Computed

    private var currentAttachments: [AttachmentItem] {
        noteStore.getAttachments(for: note)
            .filter { !deletedAttachmentIDs.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 主内容
            VStack(spacing: 0) {
                // 标签区域（仅预览模式显示）
                if !isEditMode && !note.tags.isEmpty {
                    tagSection
                    Divider()
                }
                
                // 文本编辑/预览区
                textEditorSection

                // 附件缩略图区域
                if !currentAttachments.isEmpty {
                    Divider()
                    attachmentStripSection
                }

                // 时间信息
                if onPublish == nil {
                    timeInfoSection
                }

                // 富文本工具栏（仅编辑模式 + 键盘聚焦时显示）
                if isEditMode && showRichTextBar && isEditorFocused {
                    Divider()
                    RichTextToolbar(
                        onBold: { applyTextFormat(.bold) },
                        onItalic: { applyTextFormat(.italic) },
                        onBulletList: { insertPrefix("• ") },
                        onNumberedList: { insertPrefix("1. ") },
                        onDismissKeyboard: {
                            textViewCoordinator?.blur()
                        }
                    )
                }
                
                // 底部工具栏（仅编辑模式显示）
                if isEditMode {
                    Divider()
                    bottomToolbar
                }
            }
            
            // 悬浮语音按钮（底部中央）- 只在编辑模式显示
            if isEditMode {
                ZStack(alignment: .bottom) {
                    if toolbarSettings.isVoiceInputEnabled {
                        // 语音输入悬浮窗口（录音时显示）
                        VoiceInputOverlay(
                            transcript: speechRecognizer.currentTranscript,
                            isRecording: speechRecognizer.isRecording,
                            dragOffset: 0, // 内部不移动，改为由外部控制整体Offset
                            shouldCancel: voiceDragOffset < -80
                        )
                        .offset(y: voiceDragOffset) // 跟随拖拽
                        .padding(.bottom, 80)
                        .opacity(speechRecognizer.isRecording ? 1 : 0)
                        .scaleEffect(speechRecognizer.isRecording ? 1 : 0.5, anchor: .bottom)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: speechRecognizer.isRecording)
                        
                        // 麦克风按钮（始终存在以接收手势，录音时变透明）
                        floatingVoiceButton
                            .padding(.bottom, 80)
                            .opacity(speechRecognizer.isRecording ? 0 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(true)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isEditMode {
                    // 编辑模式：undo + redo + ... + 完成
                    Button {
                        performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                    }
                    .disabled(!undoRedoManager.canUndo)

                    Button {
                        performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                    }
                    .disabled(!undoRedoManager.canRedo)

                    Menu {
                        Button {
                            showTagManagement = true
                        } label: {
                            Label("管理标签", systemImage: "tag")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                    }

                    Button {
                        exitEditMode()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundColor(undoRedoManager.canUndo || undoRedoManager.canRedo ? .orange : .secondary)
                    }
                    .disabled(!undoRedoManager.canUndo && !undoRedoManager.canRedo)
                } else {
                    // 预览模式：... + pencil
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                    }

                    Button {
                        enterEditMode()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .onAppear { loadContent() }
        .onDisappear { 
            cleanupOnExit() 
        }
        .onChange(of: content) { 
            // 仅在编辑模式下记录和保存
            guard isEditMode else { return }
            
            // 标记已编辑
            wasEdited = true
            
            // 记录文本变化到undo管理器（排除undo/redo操作本身，避免循环）
            if content != previousContent && !isPerformingUndoRedo {
                undoRedoManager.recordAction(.textChange(previousText: previousContent, newText: content))
                previousContent = content
                
                // 延迟实时保存（防抖：1秒后保存）
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    if !Task.isCancelled {
                        await MainActor.run {
                            saveContentInEditMode()
                        }
                    }
                }
            }
        }
        .onChange(of: currentAttachments.count) {
            // 仅在编辑模式下标记已编辑
            guard isEditMode else { return }
            wasEdited = true
        }
        .onChange(of: note.tags) {
            // 仅在编辑模式下标记已编辑
            guard isEditMode else { return }
            wasEdited = true
        }
        .onChange(of: note.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .onChange(of: isEditorFocused) { onFocusChange?(isEditorFocused) }
        //.onChange(of: speechRecognizer.currentTranscript) {
        //    handleRealtimeTranscript()
        //}
        .onChange(of: speechRecognizer.isRecording) {
            if !speechRecognizer.isRecording {
                finalizeSpeechInsertion()
            }
        }
        .onChange(of: isVoiceButtonPressed) {
            // 当按钮松开时，停止录音
            // 注意：这里需要无条件停止，哪怕 speechRecognizer.isRecording 暂时为 false
            // 因为如果是首次授权过程，isRecording 还没变成 true，但用户松手了，意图是停止
            if !isVoiceButtonPressed {
                speechRecognizer.stopRecording()
                voiceDragOffset = 0
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // 如果应用失去焦点（如弹出权限请求），且正在录音，则强制停止
            if newPhase != .active && isVoiceButtonPressed {
                isVoiceButtonPressed = false
            }
        }
        // 各类选择器
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onCaptureImage: { image in saveImage(image, type: .photo) },
                onCaptureVideo: { url in saveVideo(url) }
            )
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(
                onPickImage: { image in saveImage(image, type: .photo) },
                onPickVideo: { url in saveVideo(url) }
            )
        }
        .sheet(item: $activeScanMode) { mode in
            DocumentScannerView { images in handleScannedImages(images, mode: mode) }
        }
        .sheet(isPresented: $showAudioRecorder) {
            AudioRecorderSheet(note: note)
                .environment(noteStore)
                .onDisappear {
                    // 检测音频附件的添加
                    let currentIDs = Set(currentAttachments.map { $0.id })
                    let newIDs = currentIDs.subtracting(previousAttachmentIDs)
                    for id in newIDs {
                        undoRedoManager.recordAction(.attachmentAdded(attachmentID: id))
                    }
                    previousAttachmentIDs = currentIDs
                    
                    if !newIDs.isEmpty {
                        saveContentInEditMode()
                    }
                }
        }
        .sheet(isPresented: $showFilePicker) {
            FilePickerView { urls in handlePickedFiles(urls) }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { coordinate, image in
                saveLocation(coordinate: coordinate, snapshot: image)
            }
        }
        .fullScreenCover(isPresented: $showPaintingCanvas) {
            PaintingView { imageData in
                saveImage(UIImage(data: imageData)!, type: .drawing)
            }
        }
        .sheet(item: $selectedAttachment) { att in
            AttachmentViewerSheet(attachment: att)
                .environment(noteStore)
        }
        .sheet(isPresented: $showTagManagement) {
            TagManagementSheet(note: note)
                .environment(noteStore)
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                // 标记正在删除，防止 cleanupOnExit 干扰
                isDeleting = true
                
                // 清空undo/redo历史
                undoRedoManager.clear()
                note.undoRedoHistoryData = nil
                
                noteStore.softDeleteNote(note)
                dismiss()
            }
        } message: {
            Text("确定要删除这条记录吗？")
        }
    }

    // MARK: - 标签区域（预览模式）
    
    private var tagSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(note.tags) { tag in
                    Text(tag.name)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 文本编辑区

    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            CursorTrackingTextView(
                text: $content,
                cursorPosition: $cursorPosition,
                isEditable: isEditMode,
                onFocusChange: { focused in
                    isEditorFocused = focused
                },
                onUndoStateChange: { undo, redo in
                    // UITextView 的 undo/redo 状态已不再使用，改用 UndoRedoManager
                },
                onCoordinatorReady: { coordinator in
                    textViewCoordinator = coordinator
                    // 自动聚焦（编辑模式时）
                    if isEditMode {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            coordinator.focus()
                            let len = (self.content as NSString).length
                            if len > 0 {
                                coordinator.setCursor(to: len)
                            }
                        }
                    }
                }
            )

            if content.isEmpty && !speechRecognizer.isRecording {
                Text(isEditMode ? "开始输入..." : "暂无内容")
                    .foregroundColor(Color(.placeholderText))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 悬浮语音按钮
    
    private var floatingVoiceButton: some View {
        ZStack {
            Circle()
                .fill(buttonColor)
                .frame(width: 64, height: 64)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundColor(.white)
        }
        .scaleEffect(isVoiceButtonPressed ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isVoiceButtonPressed)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: voiceDragOffset)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleVoiceDragChanged(value)
                }
                .onEnded { value in
                    handleVoiceDragEnded(value)
                }
        )
    }
    
    private var buttonColor: Color {
        if !isVoiceButtonPressed {
            return .accentColor
        }
        return voiceDragOffset < -80 ? .red : .green
    }


    // MARK: - 附件缩略图条

    private var attachmentStripSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(currentAttachments) { attachment in
                    AttachmentThumbnailView(
                        attachment: attachment,
                        shouldSaveOnDelete: false,
                        showDeleteButton: isEditMode,
                        onDelete: {
                            withAnimation {
                                _ = deletedAttachmentIDs.insert(attachment.id)
                            }
                            undoRedoManager.recordAction(.attachmentDeleted(attachmentID: attachment.id))
                            saveContentInEditMode()
                        }
                    )
                    .frame(width: 100, height: 100)
                    .onTapGesture {
                        selectedAttachment = attachment
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 时间信息显示
    
    private var timeInfoSection: some View {
        HStack {
            Spacer()
            Text(note.createdAt.formattedFull)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 底部工具栏（展开式附件选项）

    private var bottomToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(toolbarSettings.activeItems) { item in
                    toolButton(for: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
    
    private func toolButton(for item: ToolbarItemType) -> some View {
        ToolbarButton(
            icon: item.icon
        ) {
            switch item {
            case .camera: showCamera = true
            case .photo: showPhotoPicker = true
            case .audio: showAudioRecorder = true
            case .folder: showFilePicker = true
            case .location: showLocationPicker = true
            case .drawing: showPaintingCanvas = true
            case .scanText:
                activeScanMode = .textExtraction
            case .scanDocument:
                activeScanMode = .documentScan
            }
        }
    }
    
    // MARK: - 工具栏按钮组件
    
    private struct ToolbarButton: View {
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    // MARK: - Actions
    
    /// 进入编辑模式
    private func enterEditMode() {
        isEditMode = true
        
        // 聚焦光标到末尾
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            textViewCoordinator?.focus()
            let len = (content as NSString).length
            if len > 0 {
                textViewCoordinator?.setCursor(to: len)
            }
        }
    }
    
    /// 退出编辑模式（完成编辑）
    private func exitEditMode() {
        // 取消延迟保存任务
        saveTask?.cancel()
        
        // 执行实际的附件删除（只在完成时删除）
        for attachmentID in deletedAttachmentIDs {
            if let attachment = noteStore.getAttachments(for: note).first(where: { $0.id == attachmentID }) {
                noteStore.deleteAttachment(attachment, shouldSave: true)
            }
        }
        deletedAttachmentIDs.removeAll()
        
        // 清空待删除列表
        note.pendingDeletedAttachmentIDs = []
        
        // 清空undo/redo历史（完成编辑后清空）
        undoRedoManager.clear()
        note.undoRedoHistoryData = nil
        
        // 取消键盘焦点
        textViewCoordinator?.blur()
        
        // 震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 切换到预览模式
        isEditMode = false
    }
    
    /// 执行撤销操作
    private func performUndo() {
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
    private func performRedo() {
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
    private func saveContentInEditMode() {
        // 更新笔记内容
        if let latestText = textViewCoordinator?.getText() {
            note.content = latestText
        } else {
            note.content = content
        }
        
        // 注意：不在编辑模式时删除附件，只是在 UI 中隐藏
        // 实际删除只在点击"完成"或退出时进行
        
        // 保存待删除的附件ID列表
        note.pendingDeletedAttachmentIDs = Array(deletedAttachmentIDs)
        
        // 保存undo/redo历史到数据库
        note.undoRedoHistoryData = undoRedoManager.serializeHistory()
        
        // 保存到数据库
        noteStore.updateNote(note)
        try? noteStore.modelContext.save()
        
        // 更新基准状态
        initialContent = note.content
        initialAttachmentCount = currentAttachments.count
        // 注意：不清空 deletedAttachmentIDs，保持删除状态直到完成编辑
        initialTagIDs = Set(note.tags.map { $0.id })
        wasEdited = false
    }

    private func loadContent() {
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
        
        cursorPosition = (content as NSString).length

        // 加载undo/redo历史（如果存在）
        if let historyData = note.undoRedoHistoryData {
            undoRedoManager.loadHistory(from: historyData)
        } else {
            // 新笔记或没有历史，清空管理器
            undoRedoManager.clear()
        }
        
        // 初始化编辑模式
        isEditMode = startInEditMode || onPublish != nil

        hasLoaded = true
    }

    private func cleanupOnExit() {
        // 如果正在删除，跳过清理（避免覆盖删除状态）
        guard !isDeleting else { return }
        
        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        
        // 取消任何待处理的保存任务
        saveTask?.cancel()
        
        // 获取最新文本内容
        let latestText = textViewCoordinator?.getText() ?? content
        
        // 最终保存（确保所有内容都持久化）
        if latestText != note.content {
            note.content = latestText
            note.updatedAt = Date()
        }
        
        // 保存编辑状态（保留undo/redo历史，下次可继续使用）
        note.pendingDeletedAttachmentIDs = Array(deletedAttachmentIDs)
        note.undoRedoHistoryData = undoRedoManager.serializeHistory()
        
        // 统一保存
        try? noteStore.modelContext.save()
    }

    // MARK: - 语音输入

    /// 处理语音按钮拖拽变化
    private func handleVoiceDragChanged(_ value: DragGesture.Value) {
        // 首次按下
        if !isVoiceButtonPressed {
            isVoiceButtonPressed = true
            voiceDragOffset = 0
            
            // 震动反馈
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            beginSpeechInsertion()
            speechRecognizer.startRecording()
        }
        
        // 更新拖拽偏移（只允许向上拖）
        let newOffset = value.translation.height < 0 ? value.translation.height : 0
        
        // 检测是否进入取消状态
        let wasInCancelZone = voiceDragOffset < -80
        let isInCancelZone = newOffset < -80
        
        // 进入取消区域时震动
        if !wasInCancelZone && isInCancelZone {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.warning)
        }
        
        voiceDragOffset = newOffset
    }
    
    /// 处理语音按钮拖拽结束
    private func handleVoiceDragEnded(_ value: DragGesture.Value) {
        let shouldCancel = voiceDragOffset < -80
        
        // 设置取消标记（在停止录音之前）
        shouldCancelVoiceInput = shouldCancel
        
        // 震动反馈
        if shouldCancel {
            // 取消操作 - 强烈震动
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
        } else {
            // 正常完成 - 轻微震动
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        
        // 松开按钮（会触发 onChange 停止录音）
        isVoiceButtonPressed = false
    }

    private func toggleVoiceInput() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            beginSpeechInsertion()
            speechRecognizer.startRecording()
        }
    }

    /// 开始语音输入：记录光标位置，分割内容为前后两段
    private func beginSpeechInsertion() {
        let nsContent = content as NSString
        let total = nsContent.length

        // 如果光标不在文本内（未聚焦），插入到末尾
        let insertAt: Int
        if isEditorFocused && cursorPosition >= 0 && cursorPosition <= total {
            insertAt = cursorPosition
        } else {
            insertAt = total
        }

        speechInsertionIndex = insertAt

        // 分割内容
        let startIndex = content.index(content.startIndex, offsetBy: min(insertAt, content.count))
        contentBeforeSpeech = String(content[content.startIndex..<startIndex])
        contentAfterSpeech = String(content[startIndex..<content.endIndex])
        lastTranscriptLength = 0
        
        // 重置取消标记
        shouldCancelVoiceInput = false
    }

    /// 实时处理语音转文字：把 transcript 拼接到光标位置
    private func handleRealtimeTranscript() {
        guard speechRecognizer.isRecording else { return }

        let transcript = speechRecognizer.currentTranscript
        let newContent = contentBeforeSpeech + transcript + contentAfterSpeech
        content = newContent

        // 将光标移到 transcript 末尾
        let newCursorPos =
            (contentBeforeSpeech as NSString).length + (transcript as NSString).length
        cursorPosition = newCursorPos
        lastTranscriptLength = (transcript as NSString).length
    }

    /// 语音结束：最终确认内容
    private func finalizeSpeechInsertion() {
        // 如果用户选择取消
        if shouldCancelVoiceInput {
            // 恢复到录音前的内容（不触发保存）
            content = contentBeforeSpeech + contentAfterSpeech
            speechRecognizer.currentTranscript = ""
            shouldCancelVoiceInput = false
        } else {
            // 正常完成：保存识别的文字
            let finalTranscript = speechRecognizer.currentTranscript
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if finalTranscript.isEmpty {
                // 没有识别到内容，恢复原文
                content = contentBeforeSpeech + contentAfterSpeech
            } else {
                // 保存识别的内容到光标位置
                content = contentBeforeSpeech + finalTranscript + contentAfterSpeech
                
                // 更新光标位置到插入文字的末尾
                let newCursorPos = (contentBeforeSpeech as NSString).length + (finalTranscript as NSString).length
                cursorPosition = newCursorPos
                
                // 标记已编辑（不自动保存）
                wasEdited = true
            }
            
            speechRecognizer.currentTranscript = ""
        }
        
        // 清理临时状态
        contentBeforeSpeech = ""
        contentAfterSpeech = ""
        lastTranscriptLength = 0
    }

    // MARK: - 富文本格式

    /// 应用 Markdown 格式（加粗/斜体）
    private func applyTextFormat(_ format: TextFormat) {
        guard let coordinator = textViewCoordinator,
            let range = coordinator.getSelectedRange(),
            let fullText = coordinator.getText()
        else { return }

        let marker: String
        switch format {
        case .bold: marker = "**"
        case .italic: marker = "*"
        }

        if range.length > 0 {
            // 有选中文字：包裹标记
            let nsText = fullText as NSString
            let selected = nsText.substring(with: range)
            let replacement = "\(marker)\(selected)\(marker)"
            coordinator.replaceRange(range, with: replacement)
        } else {
            // 无选中：插入占位符并放置光标
            let placeholder = "\(marker)文本\(marker)"
            coordinator.insertAtCursor(placeholder)
        }
    }

    /// 在当前行开头插入前缀（标题、列表等）
    private func insertPrefix(_ prefix: String) {
        guard let coordinator = textViewCoordinator,
            let range = coordinator.getSelectedRange(),
            let fullText = coordinator.getText()
        else { return }

        let nsText = fullText as NSString
        // 找到当前行的开头
        var lineStart = range.location
        while lineStart > 0 && nsText.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let insertRange = NSRange(location: lineStart, length: 0)
        coordinator.replaceRange(insertRange, with: prefix)
    }

    // MARK: - 处理扫描结果

    private func handleScannedImages(_ images: [UIImage], mode: ScanMode) {
        print("📷 Handling scanned images. Mode: \(mode)")
        switch mode {
        case .textExtraction:
            print("📝 Starting text recognition for \(images.count) images...")
            // ... (rest of logic)
            TextRecognizer.recognizeText(from: images) { text in
                print("✅ Recognized text length: \(text.count)")
                if text.isEmpty {
                    print("⚠️ No text recognized")
                }
                guard !text.isEmpty else { return }
                
                // 确保在主线程更新 UI
                if !content.isEmpty { content += "\n" }
                content += text
                
                // 触发保存
                wasEdited = true
            }
            
        case .documentScan:
            print("📄 Saving \(images.count) document images...")
            for image in images {
                saveImage(image, type: .scannedDocument)
            }
        }
    }

    // MARK: - 处理文件选择

    private func handlePickedFiles(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let attachment = noteStore.addAttachment(
                to: note,
                type: .file,
                data: data,
                fileExtension: url.pathExtension,
                shouldSave: false // 手动发布前不持久化到数据库
            )
            
            // 记录到undo管理器
            if let attachmentID = attachment?.id {
                undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
                previousAttachmentIDs.insert(attachmentID)
                saveContentInEditMode()
            }
        }
        wasEdited = true
    }

    // MARK: - 保存位置附件
    
    private func saveLocation(coordinate: CLLocationCoordinate2D, snapshot: UIImage) {
        let locationData: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: locationData),
              let snapshotData = snapshot.jpegData(compressionQuality: 0.8) else { return }
        
        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .location,
            data: jsonData,
            thumbnailData: snapshotData,
            fileExtension: "json",
            shouldSave: false // 确保不自动触发 context save
        )
        
        // 记录到undo管理器
        if let attachmentID = attachment?.id {
            undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
            previousAttachmentIDs.insert(attachmentID)
            saveContentInEditMode()
        }
        
        wasEdited = true
    }

    // MARK: - 保存图片附件

    private func saveImage(_ image: UIImage, type: AttachmentType) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        // 生成缩略图
        let thumbSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }
        let thumbnailData = thumbImage.jpegData(compressionQuality: 0.6)

        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: type,
            data: imageData,
            thumbnailData: thumbnailData,
            fileExtension: "jpg",
            shouldSave: false // 确保不自动触发 context save
        )
        
        // 记録到undo管理器
        if let attachmentID = attachment?.id {
            undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
            previousAttachmentIDs.insert(attachmentID)
            saveContentInEditMode()
        }
        
        wasEdited = true
    }

    // MARK: - 保存视频附件

    private func saveVideo(_ url: URL) {
        guard let videoData = try? Data(contentsOf: url) else { return }

        let thumbnailData = Self.generateVideoThumbnail(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .video,
            data: videoData,
            thumbnailData: thumbnailData,
            fileExtension: ext,
            shouldSave: false // 确保不自动触发 context save
        )
        
        // 记录到undo管理器
        if let attachmentID = attachment?.id {
            undoRedoManager.recordAction(.attachmentAdded(attachmentID: attachmentID))
            previousAttachmentIDs.insert(attachmentID)
            saveContentInEditMode()
        }
        
        wasEdited = true
    }

    /// 从视频生成缩略图
    static func generateVideoThumbnail(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)

        var resultData: Data?
        let semaphore = DispatchSemaphore(value: 0)
        
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
            if let cgImage = cgImage {
                resultData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return resultData
    }
}


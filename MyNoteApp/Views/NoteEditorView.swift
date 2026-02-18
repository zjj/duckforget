import AVFoundation
import SwiftUI
import CoreLocation
import SwiftData

/// 记录编辑器 - 支持文字输入、语音转文字、附件管理
struct NoteEditorView: View {
    let note: NoteItem
    var isEmbedded: Bool = false
    var onFocusChange: ((Bool) -> Void)? = nil
    var onPublish: (() -> Void)? = nil
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toolbarSettings: ToolbarSettings

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

    // 撤销/重做状态
    @State private var canUndo = false
    @State private var canRedo = false
    
    // 标签管理
    @State private var showTagManagement = false

    // 富文本工具栏
    @State private var showRichTextBar = false

    // 编辑状态追踪
    @State private var wasEdited = false
    @State private var hasPublished = false // 标记是否已点击发布按钮保存
    @State private var editedContent = "" // 临时编辑内容，只有点击发布才会真正保存
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
    
    // 检测是否有实际的内容或附件变化
    private var hasActualChanges: Bool {
        let contentChanged = content != initialContent
        let attachmentsChanged = currentAttachments.count != initialAttachmentCount
        // 标签变化（集合比较）
        let currentTagIDs = Set(note.tags.map { $0.id })
        let tagsChanged = currentTagIDs != initialTagIDs
        
        return contentChanged || attachmentsChanged || tagsChanged
    }

    // MARK: - Body

    /// 是否使用内嵌工具栏（嵌入 dashboard 且有 onPublish 时，nav bar 不可见）
    private var useInlineToolbar: Bool {
        isEmbedded && onPublish != nil
    }

    var body: some View {
        ZStack {
            // 主内容
            VStack(spacing: 0) {
                // 文本编辑区
                textEditorSection

                // 时间信息（仅编辑模式显示，且如果内容不为空）
                if onPublish == nil {
                    timeInfoSection
                }

                // 附件缩略图区域
                if !currentAttachments.isEmpty {
                    Divider()
                    attachmentStripSection
                }

                // 富文本工具栏
                if showRichTextBar && isEditorFocused {
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
                
                Divider()

                // 底部工具栏
                bottomToolbar
            }
            .safeAreaInset(edge: .top) {
                // 内嵌工具栏（fullPage newNote 组件使用，作为 safeAreaInset 确保不被键盘遮挡，且悬停在顶部）
                if useInlineToolbar {
                    VStack(spacing: 0) {
                        embeddedToolbar
                        Divider()
                    }
                }
            }
            
            // 悬浮语音按钮（底部中央）
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
            // .ignoresSafeArea(.keyboard) // 移除此行，让悬浮按钮跟随键盘上移
            .allowsHitTesting(true)
        }
        .navigationBarTitleDisplayMode(isEmbedded ? .automatic : .inline)
        .toolbar(isEmbedded ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            // 如果是嵌入模式，不再向导航栏添加按钮（使用自定义嵌入式工具栏）
            if !isEmbedded {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        textViewCoordinator?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                    }
                    .disabled(!canUndo)

                    Button {
                        textViewCoordinator?.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                    }
                    .disabled(!canRedo)
                    
                    // 菜单 - 新建和编辑都显示
                    Menu {
                        Button {
                            showTagManagement = true
                        } label: {
                            Label("管理标签", systemImage: "tag")
                        }
                        
                        // 仅编辑模式或已发布过才显示导出/删除
                        if onPublish == nil || hasPublished {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis") // 不带圆圈
                            .font(.system(size: 16))
                    }
                    
                    // 发布按钮 - 新建和编辑都显示
                    Button {
                        performPublish()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(!hasActualChanges)
                }
            }
        }
        .onAppear { loadContent() }
        .onDisappear { 
            // 无论嵌入与否，都需要清理逻辑（特别是针对 temporary note 的删除）
            cleanupOnExit() 
        }
        .onChange(of: content) { 
            // 标记已编辑
            wasEdited = true 
        }
        .onChange(of: currentAttachments.count) {
            // 标记已编辑，确保删除或添加附件都能触发 rollback/publish 逻辑
            wasEdited = true
        }
        .onChange(of: note.tags) {
             // 标签发生变化（如从Sheet返回），标记已编辑
             wasEdited = true
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
            if !isVoiceButtonPressed && speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
                voiceDragOffset = 0
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
                noteStore.softDeleteNote(note)
                dismiss()
            }
        } message: {
            Text("确定要删除这条记录吗？")
        }
    }

    // MARK: - 内嵌工具栏（fullPage 组件顶部）

    /// 当 NoteEditorView 嵌入 dashboard 且 nav bar 不可见时，
    /// 在视图内部顶端渲染 undo/redo/发布 按钮
    private var embeddedToolbar: some View {
        HStack(spacing: 16) {
            Button {
                textViewCoordinator?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16))
            }
            .disabled(!canUndo)
            
            Button {
                textViewCoordinator?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 16))
            }
            .disabled(!canRedo)
            
            if onPublish != nil {
                Button {
                    performPublish()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.attachments.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - 文本编辑区

    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            CursorTrackingTextView(
                text: $content,
                cursorPosition: $cursorPosition,
                onFocusChange: { focused in
                    isEditorFocused = focused
                },
                onUndoStateChange: { undo, redo in
                    canUndo = undo
                    canRedo = redo
                },
                onCoordinatorReady: { coordinator in
                    textViewCoordinator = coordinator
                    // 如果是新建/编辑页面，自动聚焦
                    // 延迟一点点以确保视图完全准备好
                    if onPublish != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            coordinator.focus()
                            // 确保光标在最后（loadContent 中已经设置了 cursorPosition，这里再次确保一下同步）
                            let len = (self.content as NSString).length
                            if len > 0 {
                                coordinator.setCursor(to: len)
                            }
                        }
                    }
                }
            )

            if content.isEmpty && !speechRecognizer.isRecording {
                Text("开始输入...")
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
                        shouldSaveOnDelete: false, // 在编辑器中删除，只有点保存才执行
                        onDelete: {
                            // 立即在 UI 上隐藏该附件
                            withAnimation {
                                _ = deletedAttachmentIDs.insert(attachment.id)
                            }
                        }
                    )
                    .frame(width: 100, height: 100)
                    .onTapGesture {
                        selectedAttachment = attachment
                    }
/* Lines 390-399 omitted */
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

    private func loadContent() {
        guard !hasLoaded else { return }
        content = note.content
        initialContent = note.content // 保存初始内容
        initialAttachmentCount = currentAttachments.count // 保存初始附件数量
        
        // 载入标签状态
        initialTagIDs = Set(note.tags.map { $0.id })
        
        cursorPosition = (content as NSString).length

        // 清除初始加载产生的 undo 栈，确保新记录无法 undo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textViewCoordinator?.clearUndoStack()
        }

        hasLoaded = true
    }

    private func cleanupOnExit() {
        // 如果是新建记录模式（onPublish != nil）
        if onPublish != nil {
            // 如果从未发布过，直接删
            if !hasPublished {
                noteStore.permanentlyDeleteNote(note)
                return
            }
            // 如果发布过，但后续有未保存的修改，且用户希望不自动保存
            // 则应当回滚这些修改（恢复到上次发布的状态）
            if hasPublished && hasActualChanges {
                 noteStore.modelContext.rollback()
            }
            return
        }

        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        
        // 编辑模式：如果有任何未发布的改动（内容或附件），执行回滚
        // 这样可以丢弃那些虽然已 inserted 到 context 但尚未 checked (save) 的附件
        if !hasPublished && hasActualChanges {
            // 注意：rollback 只能撤销内存中的 SwiftData 对象
            // 附件对应的物理文件如果没被 cleanup，会暂时滞留在磁盘
            noteStore.modelContext.rollback()
        }
    }

    private func performPublish() {
        // 1. 标记已发布
        hasPublished = true
        
        // 2. 从 UITextView 获取最新文本以避免 State 延迟
        if let latestText = textViewCoordinator?.getText() {
             note.content = latestText
        } else {
             note.content = content
        }
        
        // 3. 确保内容被保存到数据库
        if !note.content.isEmpty || !note.attachments.isEmpty {
            noteStore.updateNote(note)
            try? noteStore.modelContext.save()
        }
        
        // 4. 反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 5. 更新基准状态以便用户继续编辑
        // 不再自动退出，而是保留在当前页面
        initialContent = note.content
        initialAttachmentCount = currentAttachments.count
        
        // 保存成功后，清理已删除ID集合
        deletedAttachmentIDs.removeAll()
        
        // 更新标签基准状态
        initialTagIDs = Set(note.tags.map { $0.id })
        
        wasEdited = false
        
        // 如果是新建模式（onPublish != nil），标记 hasPublished = true，防止退出时整条删除
        if onPublish != nil {
            hasPublished = true
        } else {
            // 如果是编辑模式，重置 hasPublished = false
            // 这样后续若有修改但未再次点击保存，退出时可以正确触发 rollback
            hasPublished = false
        }
    }

    private func saveContent() {
        // 已废弃自动保存功能
        // 现在所有保存操作都通过 performPublish 手动触发
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
            noteStore.addAttachment(
                to: note,
                type: .file,
                data: data,
                fileExtension: url.pathExtension,
                shouldSave: false // 手动发布前不持久化到数据库
            )
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
        
        // 使用 addAttachmentWithThumbnail 存储
        // thumbnailData: snapshot
        // data: json string
        // fileExtension: json
        noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .location,
            data: jsonData,
            thumbnailData: snapshotData,
            fileExtension: "json",
            shouldSave: false // 确保不自动触发 context save
        )
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

        noteStore.addAttachmentWithThumbnail(
            to: note,
            type: type,
            data: imageData,
            thumbnailData: thumbnailData,
            fileExtension: "jpg",
            shouldSave: false // 确保不自动触发 context save
        )
        wasEdited = true
    }

    // MARK: - 保存视频附件

    private func saveVideo(_ url: URL) {
        guard let videoData = try? Data(contentsOf: url) else { return }

        let thumbnailData = Self.generateVideoThumbnail(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .video,
            data: videoData,
            thumbnailData: thumbnailData,
            fileExtension: ext,
            shouldSave: false // 确保不自动触发 context save
        )
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


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

    // 语音实时插入状态
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
    @State private var showAttachmentViewer = false
    @State private var selectedAttachmentIndex: Int = 0
    
    // 附件显示模式
    enum AttachmentDisplayMode {
        case grid      // 网格模式
        case fullSize  // 原图模式
    }
    @State private var attachmentDisplayMode: AttachmentDisplayMode = .grid

    // 语音输入
    @StateObject private var speechRecognizer = SpeechRecognizer()

    // 编辑器焦点
    @FocusState private var editorFocused: Bool

    // 撤销/重做管理器
    @StateObject private var undoRedoManager = UndoRedoManager()
    
    // 编辑内容追踪
    @State private var previousContent = "" // 用于记录文本变化
    @State private var saveTask: Task<Void, Never>? // 用于延迟保存
    @State private var previousAttachmentIDs: Set<UUID> = [] // 用于跟踪附件变化
    @State private var isPerformingUndoRedo = false // 标记是否正在执行撤销/重做操作
    
    // 标签管理
    @State private var showTagManagement = false

    // 浮动上下文菜单
    @State private var showFloatingMenu = false
    @State private var floatingMenuHasSelection = false
    @State private var floatingMenuIsTodoLine = false
    @State private var floatingMenuIsTodoChecked = false
    @State private var floatingMenuPosition: CGPoint = .zero
    
    // 格式工具栏展开状态
    @State private var showExpandedFormatBar = false
    
    // 当前行待办状态
    @State private var currentLineIsTodo = false
    @State private var currentLineIsTodoChecked = false
    @State private var todoToggleButtonPressed = false

    // Markdown 编辑器协调器
    @State private var markdownCoordinator: MarkdownTextView.Coordinator?
    // 是否在协调器就绪后自动聚焦（替代计时器，避免竞争条件）
    @State private var shouldAutoFocus = false

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

    // 导出
    @State private var showExportPicker = false
    @State private var isExporting = false
    @State private var exportFileURL: URL? = nil
    @State private var showShareSheet = false
    @State private var exportError: String? = nil
    @State private var showExportError = false

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

    /// 浮动菜单锚点：始终放在屏幕顶部区域，避免被键盘和工具栏遮挡
    private var floatingMenuAnchor: CGPoint {
        let screen = UIScreen.main.bounds
        let margin: CGFloat = 16
        let safeTop: CGFloat = 60  // 状态栏 + 导航栏高度
        
        // X: 居中屏幕
        let x = screen.width / 2
        
        // Y: 菜单顶部紧贴导航栏下方，确保不被键盘遮挡
        let y = safeTop + margin + 160  // 菜单中心点≈顶部偏下
        
        return CGPoint(x: x, y: y)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 主内容
            Group {
                if !isEditMode {
                    // 预览模式（网格/原图）：整个页面可滚动，内容顶部对齐
                    ScrollView {
                        VStack(spacing: 0) {
                            mainContentView
                        }
                    }
                } else {
                    // 编辑模式：普通 VStack，TextEditor 可垂直伸展
                    VStack(spacing: 0) {
                        mainContentView
                    }
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

            // 浮动上下文菜单
            if showFloatingMenu {
                // 半透明背景（点击关闭）
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            showFloatingMenu = false
                        }
                    }
                    .zIndex(10)

                FloatingContextMenu(
                    isTodoLine: floatingMenuIsTodoLine,
                    isTodoChecked: floatingMenuIsTodoChecked,
                    onToggleTodo: {
                        markdownCoordinator?.toggleTodoOnCurrentLine()
                    },
                    onFormatAction: { action in
                        applyFormatAction(action)
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            showFloatingMenu = false
                        }
                    }
                )
                .position(floatingMenuAnchor)
                .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                .zIndex(11)
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
                            Label("标签", systemImage: "tag")
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
                            .font(.system(size: 16))
                            .scaleEffect((undoRedoManager.canUndo || undoRedoManager.canRedo) ? 1.0 : 0.8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: (undoRedoManager.canUndo || undoRedoManager.canRedo))
                            .scaleEffect((undoRedoManager.canUndo || undoRedoManager.canRedo) ? 1.0 : 0.8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: (undoRedoManager.canUndo || undoRedoManager.canRedo))
                    }
                    .disabled(!undoRedoManager.canUndo && !undoRedoManager.canRedo)
                    .disabled(!undoRedoManager.canUndo && !undoRedoManager.canRedo)
                } else {
                    // 预览模式：... + pencil
                    Menu {
                        Button {
                            showExportPicker = true
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }

                        Divider()

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
        .onChange(of: scenePhase) { _, newPhase in
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
        .sheet(isPresented: $showAttachmentViewer) {
            NavigableAttachmentViewerSheet(
                attachments: currentAttachments,
                currentIndex: $selectedAttachmentIndex
            )
            .environment(noteStore)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
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
        // ---- 导出格式选择 ----
        .confirmationDialog("选择导出格式", isPresented: $showExportPicker, titleVisibility: .visible) {
            Button("PDF") { triggerExport(format: .pdf) }
            Button("纯文本（.txt）") { triggerExport(format: .txt) }
            Button("Markdown（.md）") { triggerExport(format: .markdown) }
            Button("ZIP 归档（含附件）") { triggerExport(format: .zip) }
            Button("取消", role: .cancel) { }
        }
        // ---- 系统分享面板 ----
        .sheet(isPresented: $showShareSheet, onDismiss: {
            if let url = exportFileURL {
                try? FileManager.default.removeItem(at: url)
                exportFileURL = nil
            }
        }) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        // ---- 导出失败提示 ----
        .alert("导出失败", isPresented: $showExportError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(exportError ?? "未知错误")
        }
        // ---- 导出 Loading 遮罩 ----
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                        Text("正在导出…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    // MARK: - 主内容视图
    
    private var mainContentView: some View {
        Group {
            // 时间信息（预览模式置顶显示）
            if !isEditMode && onPublish == nil {
                timeInfoSection
            }

            // 标签区域（仅预览模式显示）
            if !isEditMode && !note.tags.isEmpty {
                tagSection
                Divider()
            }
            
            // 文本编辑/预览区
            textEditorSection
            
            // 文本和附件之间的分隔
            if !currentAttachments.isEmpty {
                Spacer()
                    .frame(height: 16)
            }

            // 附件缩略图区域
            if !currentAttachments.isEmpty {
                Divider()
                attachmentStripSection
            }

            // 时间信息（编辑模式底部显示）
            if isEditMode && onPublish == nil {
                timeInfoSection
            }
            
            // 底部工具栏（仅编辑模式显示）
            if isEditMode {
                Divider()
                bottomToolbar
            }
            
            // 展开的格式工具栏（在底部工具栏下方）
            if isEditMode && showExpandedFormatBar {
                Divider()
                expandedFormatToolbar
            }
        }
    }
    
    // MARK: - 标签区域（预览模式）
    
    private var tagSection: some View {
        HStack(spacing: 4) {
            ForEach(note.tags) { tag in
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                        .font(.caption2)
                    Text(tag.name)
                        .font(.caption2)
                }
            }
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 文本编辑区

    private var textEditorSection: some View {
        Group {
            if isEditMode {
                // 编辑模式：使用 MarkdownTextView（UITextView + 实时语法高亮）
                ZStack(alignment: .topLeading) {
                    MarkdownTextView(
                        text: $content,
                        isEditable: true,
                        onFocusChange: { focused in
                            isEditorFocused = focused
                        },
                        onCoordinatorReady: { coord in
                            markdownCoordinator = coord
                            if shouldAutoFocus {
                                shouldAutoFocus = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    coord.focus()
                                }
                            }
                            // 初始化时更新待办状态
                            updateCurrentLineTodoStatus()
                        },
                        onCursorLineChanged: {
                            updateCurrentLineTodoStatus()
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    if content.isEmpty && !speechRecognizer.isRecording {
                        HStack {
                            Text("开始输入...")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                // 预览模式：渲染 Markdown
                if content.isEmpty {
                    Text("暂无内容")
                        .foregroundColor(Color(.placeholderText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    MarkdownRenderView(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
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
        VStack(spacing: 0) {
            // 顶部模式切换按钮（仅预览模式显示）
            if !isEditMode && currentAttachments.count > 0 {
                HStack {
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleAttachmentDisplayMode()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: attachmentDisplayMode == .grid ? "square.grid.2x2" : "photo.on.rectangle")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .zIndex(1)
            }
            
            // 附件显示区域
            if !isEditMode {
                // 预览模式：根据模式显示
                if attachmentDisplayMode == .grid {
                    // 网格布局
                    gridAttachmentView
                } else {
                    // 原图模式
                    fullSizeAttachmentView
                }
            } else {
                // 编辑模式：横向滚动
                horizontalAttachmentView
            }
        }
        .background(Color(.systemBackground))
    }
    
    // 网格布局
    private var gridAttachmentView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
                AttachmentThumbnailView(
                    attachment: attachment,
                    shouldSaveOnDelete: false,
                    showDeleteButton: false,
                    onDelete: {}
                )
                .frame(width: 100, height: 100)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedAttachmentIndex = index
                    showAttachmentViewer = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // 原图模式（垂直列表）
    private var fullSizeAttachmentView: some View {
        VStack(spacing: 16) {
            ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
                FullSizeAttachmentView(
                    attachment: attachment,
                    noteStore: noteStore
                )
                .onTapGesture {
                    selectedAttachmentIndex = index
                    showAttachmentViewer = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // 横向滚动（编辑模式）
    private var horizontalAttachmentView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(currentAttachments.enumerated()), id: \.element.id) { index, attachment in
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
                        selectedAttachmentIndex = index
                        showAttachmentViewer = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // 切换附件显示模式
    private func toggleAttachmentDisplayMode() {
        attachmentDisplayMode = attachmentDisplayMode == .grid ? .fullSize : .grid
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

    // MARK: - 展开的格式工具栏（2行图标布局）
    
    private var expandedFormatToolbar: some View {
        let allFormats = FormatMenuSheet.FormatAction.allCases
        let halfCount = (allFormats.count + 1) / 2
        let row1 = Array(allFormats.prefix(halfCount))
        let row2 = Array(allFormats.dropFirst(halfCount))
        
        return VStack(spacing: 0) {
            // 第一行
            HStack(spacing: 0) {
                ForEach(row1) { action in
                    Button {
                        applyFormatAction(action)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 16))
                            .foregroundColor(action.color)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    
                    if action != row1.last {
                        Divider()
                            .frame(height: 24)
                    }
                }
            }
            
            Divider()
            
            // 第二行
            HStack(spacing: 0) {
                ForEach(row2) { action in
                    Button {
                        applyFormatAction(action)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 16))
                            .foregroundColor(action.color)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    
                    if action != row2.last {
                        Divider()
                            .frame(height: 24)
                    }
                }
                
                // 待办切换按钮
                Divider()
                    .frame(height: 24)
                
                Button {
                    toggleTodoCheckbox()
                } label: {
                    Text(currentLineIsTodoChecked ? "[x]" : "[ ]")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(currentLineIsTodo ? .teal : .gray)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .opacity(todoToggleButtonPressed ? 0.3 : 1.0)
                        .scaleEffect(todoToggleButtonPressed ? 1.2 : 1.0)
                }
                .disabled(!currentLineIsTodo)
                .animation(.easeInOut(duration: 0.15), value: todoToggleButtonPressed)
            }
        }
        .background(Color(.systemGray6))
    }

    // MARK: - 底部工具栏（展开式附件选项）

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // 左侧固定：Markdown 格式按钮（切换展开/收起）
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showExpandedFormatBar.toggle()
                }
            } label: {
                Image(systemName: showExpandedFormatBar ? "chevron.down" : "text.word.spacing")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 36)
            }
            
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)
            
            // 中间可滚动工具栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(toolbarSettings.activeItems.filter { $0 != .markdown }) { item in
                        toolButton(for: item)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)
            
            // 右侧固定：键盘收起按钮
            Button {
                markdownCoordinator?.blur()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 36)
            }
        }
        .frame(height: 44)
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
            case .markdown:
                // 触发 Markdown 上下文菜单
                let lineText = markdownCoordinator?.getCurrentLineText() ?? ""
                floatingMenuHasSelection = markdownCoordinator?.selectedText != nil
                floatingMenuIsTodoLine = lineText.hasPrefix("- [ ] ") || lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
                floatingMenuIsTodoChecked = lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
                
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showFloatingMenu = true
                }
            }
        }
    }
    
    // MARK: - 工具栏按钮组件
    
    private struct ToolbarButton: View {
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
            }
        }
    }

    // MARK: - Actions
    
    /// 进入编辑模式
    private func enterEditMode() {
        isEditMode = true
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
        markdownCoordinator?.blur()
        
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
        note.content = content
        
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

    // MARK: - 导出

    private func triggerExport(format: ExportFormat) {
        isExporting = true
        let service = ExportService(noteStore: noteStore)
        let capturedNote = note
        Task.detached(priority: .userInitiated) {
            do {
                let url = try service.export(note: capturedNote, format: format)
                await MainActor.run {
                    isExporting = false
                    exportFileURL = url
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    showExportError = true
                }
            }
        }
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

    private func cleanupOnExit() {
        // 如果正在删除，跳过清理（避免覆盖删除状态）
        guard !isDeleting else { return }
        
        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        
        // 取消任何待处理的保存任务
        saveTask?.cancel()
        
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

    /// 开始语音输入：将内容分割为前后两段（始终插入到末尾）
    private func beginSpeechInsertion() {
        // TextEditor 不暴露光标位置，固定插入到内容末尾
        contentBeforeSpeech = content
        contentAfterSpeech = ""
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
                // 保存识别的内容到末尾
                content = contentBeforeSpeech + finalTranscript + contentAfterSpeech
                
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

    /// 应用 Markdown 格式（加粗/斜体），插入到内容末尾
    private func applyTextFormat(_ format: TextFormat) {
        switch format {
        case .bold: applyFormatAction(.bold)
        case .italic: applyFormatAction(.italic)
        }
    }

    /// 在当前行开头插入前缀（标题、列表等）
    private func insertPrefix(_ prefix: String) {
        switch prefix {
        case "• ", "- ": applyFormatAction(.bullet)
        case "1. ": applyFormatAction(.numbered)
        default:
            if let coord = markdownCoordinator {
                coord.insertBlockAtCursor(prefix)
            } else {
                if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
                content += prefix
            }
        }
    }

    /// 切换当前行的待办复选框
    private func toggleTodoCheckbox() {
        guard currentLineIsTodo else { return }
        
        // 触发按压动画
        withAnimation(.easeInOut(duration: 0.15)) {
            todoToggleButtonPressed = true
        }
        
        // 触发震动反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // 执行切换
        markdownCoordinator?.toggleTodoOnCurrentLine()
        
        // 延迟更新状态和恢复按钮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            updateCurrentLineTodoStatus()
            withAnimation(.easeInOut(duration: 0.15)) {
                todoToggleButtonPressed = false
            }
        }
    }
    
    /// 更新当前行的待办状态
    private func updateCurrentLineTodoStatus() {
        guard let coord = markdownCoordinator else {
            currentLineIsTodo = false
            currentLineIsTodoChecked = false
            return
        }
        
        let lineText = coord.getCurrentLineText()
        currentLineIsTodo = lineText.hasPrefix("- [ ] ") || lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
        currentLineIsTodoChecked = lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ")
    }

    /// 应用格式操作（支持选中文本时包裹、无选中时插入）
    private func applyFormatAction(_ action: FormatMenuSheet.FormatAction) {
        guard let coord = markdownCoordinator else {
            // Fallback: append to end
            let text = action.rawMarkdown
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += text
            return
        }

        switch action {
        // Inline formats: wrap selection or insert with placeholder
        case .bold:
            coord.applyInlineFormat(prefix: "**", suffix: "**", placeholder: "粗体文本")
        case .italic:
            coord.applyInlineFormat(prefix: "*", suffix: "*", placeholder: "斜体文本")
        case .strikethrough:
            coord.applyInlineFormat(prefix: "~~", suffix: "~~", placeholder: "删除线文本")
        case .code:
            coord.applyInlineFormat(prefix: "`", suffix: "`", placeholder: "代码")
        case .link:
            coord.applyInlineFormat(prefix: "[", suffix: "](https://example.com)", placeholder: "链接文本")
        case .image:
            coord.applyInlineFormat(prefix: "![", suffix: "](https://example.com/image.jpg)", placeholder: "图片描述")

        // Block formats: add prefix to line or toggle
        case .h1:
            coord.applyBlockFormat(prefix: "# ")
        case .h2:
            coord.applyBlockFormat(prefix: "## ")
        case .h3:
            coord.applyBlockFormat(prefix: "### ")
        case .quote:
            coord.applyBlockFormat(prefix: "> ")
        case .bullet:
            coord.applyBlockFormat(prefix: "- ")
        case .numbered:
            coord.applyBlockFormat(prefix: "1. ")
        case .checkbox:
            coord.applyBlockFormat(prefix: "- [ ] ")

        // Special blocks: insert as-is
        case .codeBlock:
            coord.insertBlockAtCursor("```\n代码块\n```")
        case .divider:
            coord.insertBlockAtCursor("---\n")
        }
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

// MARK: - 可导航的附件查看器

/// 支持左右切换的附件查看器
struct NavigableAttachmentViewerSheet: View {
    let attachments: [AttachmentItem]
    @Binding var currentIndex: Int
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    
    private var currentAttachment: AttachmentItem {
        attachments[safe: currentIndex] ?? attachments.first!
    }
    
    private var canGoBack: Bool {
        currentIndex > 0
    }
    
    private var canGoForward: Bool {
        currentIndex < attachments.count - 1
    }
    
    private var isLocationAttachment: Bool {
        currentAttachment.type == .location
    }
    
    var body: some View {
        ZStack {
            // 主要内容
            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    VStack(spacing: 0) {
                        attachmentContentView(for: attachment)
                            .frame(maxHeight: .infinity)
                        
                        // 页面指示器（在每个附件内容下方）
                        if attachments.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<attachments.count, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == currentIndex ? Color.primary : Color.primary.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
            
            // 关闭按钮（左上角）
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary.opacity(0.7))
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.8))
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    
                    Spacer()
                }
                Spacer()
            }
            
            // 左右导航按钮（仅地图类型显示）
            if isLocationAttachment && attachments.count > 1 {
                HStack {
                    // 左侧按钮
                    if canGoBack {
                        Button {
                            withAnimation {
                                currentIndex -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.primary.opacity(0.6))
                                .shadow(radius: 4)
                        }
                        .padding(.leading, 20)
                    }
                    
                    Spacer()
                    
                    // 右侧按钮
                    if canGoForward {
                        Button {
                            withAnimation {
                                currentIndex += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.primary.opacity(0.6))
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                    }
                }
            }
        }
        .onTapGesture(count: 2) {
            dismiss()
        }
    }
    
    @ViewBuilder
    private func attachmentContentView(for attachment: AttachmentItem) -> some View {
        switch attachment.type {
        case .photo, .scannedDocument, .scannedText, .drawing:
            ImageViewer(attachment: attachment)
        case .video:
            VideoViewer(attachment: attachment)
        case .audio:
            AudioPlayerView(attachment: attachment)
        case .file:
            FilePreviewView(attachment: attachment)
        case .location:
            LocationViewer(attachment: attachment)
        }
    }
}

// 安全数组访问扩展
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 原图附件视图

/// 原图模式下显示附件的视图
struct FullSizeAttachmentView: View {
    let attachment: AttachmentItem
    let noteStore: NoteStore
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            switch attachment.type {
            case .photo, .scannedDocument, .scannedText, .drawing:
                imageView
            case .video:
                videoThumbnailView
            case .audio:
                audioPlaceholderView
            case .file:
                filePlaceholderView
            case .location:
                locationThumbnailView
            }
        }
    }
    
    private var imageView: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(4/3, contentMode: .fit)
                    
                    ProgressView()
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .aspectRatio(4/3, contentMode: .fit)
                    
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear { loadImage() }
    }
    
    private var videoThumbnailView: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .aspectRatio(16/9, contentMode: .fit)
            }
            
            Image(systemName: "play.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.white)
                .shadow(radius: 4)
        }
        .onAppear { loadThumbnail() }
    }
    
    private var audioPlaceholderView: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("音频文件")
                    .font(.headline)
                Text(attachment.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var filePlaceholderView: some View {
        HStack {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("文件")
                    .font(.headline)
                Text((attachment.fileName as NSString).pathExtension.uppercased().isEmpty ? "FILE" : (attachment.fileName as NSString).pathExtension.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var locationThumbnailView: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .aspectRatio(16/9, contentMode: .fit)
            }
            
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
                .shadow(radius: 4)
        }
        .onAppear { loadThumbnail() }
    }
    
    private func loadImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let url = noteStore.attachmentURL(for: attachment)
            if let data = try? Data(contentsOf: url),
               let loaded = UIImage(data: data) {
                DispatchQueue.main.async {
                    image = loaded
                    isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
    
    private func loadThumbnail() {
        guard let thumbnailURL = noteStore.thumbnailURL(for: attachment),
              let thumbnailData = try? Data(contentsOf: thumbnailURL),
              let thumbnailImage = UIImage(data: thumbnailData) else { return }
        image = thumbnailImage
    }
}

// MARK: - 格式菜单

struct FormatMenuSheet: View {
    let onSelect: (FormatAction) -> Void

    enum FormatAction: String, CaseIterable, Identifiable {
        case h1, h2, h3
        case bold, italic, strikethrough
        case code, codeBlock
        case quote, bullet, numbered, checkbox
        case divider
        case link, image

        var id: String { rawValue }

        var title: String {
            switch self {
            case .h1: return "h1"
            case .h2: return "h2"
            case .h3: return "h3"
            case .bold: return "粗体"
            case .italic: return "斜体"
            case .strikethrough: return "删除线"
            case .code: return "内联代码"
            case .codeBlock: return "代码块"
            case .quote: return "引用"
            case .bullet: return "无序列表"
            case .numbered: return "有序列表"
            case .checkbox: return "待办事项"
            case .divider: return "分割线"
            case .link: return "链接"
            case .image: return "图片"
            }
        }

        var icon: String {
            switch self {
            case .h1: return "textformat.size.larger"
            case .h2: return "textformat.size"
            case .h3: return "textformat.size.smaller"
            case .bold: return "bold"
            case .italic: return "italic"
            case .strikethrough: return "strikethrough"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .codeBlock: return "terminal"
            case .quote: return "text.quote"
            case .bullet: return "list.bullet"
            case .numbered: return "list.number"
            case .checkbox: return "checklist"
            case .divider: return "minus"
            case .link: return "link"
            case .image: return "photo"
            }
        }

        var preview: String {
            switch self {
            case .h1: return "# 标题"
            case .h2: return "## 标题"
            case .h3: return "### 标题"
            case .bold: return "**文本**"
            case .italic: return "*文本*"
            case .strikethrough: return "~~文本~~"
            case .code: return "`代码`"
            case .codeBlock: return "```代码块```"
            case .quote: return "> 引用文本"
            case .bullet: return "- 列表项"
            case .numbered: return "1. 列表项"
            case .checkbox: return "- [ ] 待办"
            case .divider: return "---"
            case .link: return "[文本](url)"
            case .image: return "![图片](url)"
            }
        }

        /// Returns the raw markdown string for fallback insertion
        var rawMarkdown: String {
            switch self {
            case .h1: return "# 标题\n"
            case .h2: return "## 标题\n"
            case .h3: return "### 标题\n"
            case .bold: return "**粗体文字**"
            case .italic: return "*斜体文字*"
            case .strikethrough: return "~~删除线~~"
            case .code: return "`代码`"
            case .codeBlock: return "```\n代码块\n```\n"
            case .quote: return "> 引用文本\n"
            case .bullet: return "- 列表项\n"
            case .numbered: return "1. 列表项\n"
            case .checkbox: return "- [ ] 待办事项\n"
            case .divider: return "\n---\n"
            case .link: return "[链接文本](https://example.com)"
            case .image: return "![图片描述](https://example.com/image.jpg)"
            }
        }

        var color: Color {
            switch self {
            case .h1, .h2, .h3: return .purple
            case .bold, .italic, .strikethrough: return .blue
            case .code, .codeBlock: return .orange
            case .quote: return .green
            case .bullet, .numbered, .checkbox: return .teal
            case .divider: return .gray
            case .link: return .indigo
            case .image: return .pink
            }
        }
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("插入格式")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("长按文字区域唤起")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FormatAction.allCases) { action in
                        Button {
                            onSelect(action)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(action.color.opacity(0.12))
                                        .frame(height: 44)

                                    Image(systemName: action.icon)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(action.color)
                                }

                                Text(action.title)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(action.preview)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}
// MARK: - Markdown 渲染视图

struct MarkdownRenderView: View {
    let content: String

    // Parsed block model
    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(lang: String, code: String)
        case blockquote(text: String)
        case bullet(text: String, indent: Int)
        case numbered(index: String, text: String)
        case checkbox(checked: Bool, text: String)
        case divider
        case paragraph(text: String)
        case blank
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Precompute trimmed info for bullet/checkbox detection (supports indented items)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let trimmedLine = leadingSpaces > 0 ? String(line.dropFirst(leadingSpaces)) : line

            // Code block
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fencePrefix = line.hasPrefix("```") ? "```" : "~~~"
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fencePrefix) {
                    codeLines.append(lines[i])
                    i += 1
                }
                result.append(.codeBlock(lang: lang, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Heading
            if line.hasPrefix("###### ") {
                result.append(.heading(level: 6, text: String(line.dropFirst(7))))
            } else if line.hasPrefix("##### ") {
                result.append(.heading(level: 5, text: String(line.dropFirst(6))))
            } else if line.hasPrefix("#### ") {
                result.append(.heading(level: 4, text: String(line.dropFirst(5))))
            } else if line.hasPrefix("### ") {
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))

            // Blockquote
            } else if line.hasPrefix("> ") {
                result.append(.blockquote(text: String(line.dropFirst(2))))

            // Checkbox (must check before bullet; supports indented checkboxes)
            } else if trimmedLine.hasPrefix("- [ ] ") {
                result.append(.checkbox(checked: false, text: String(trimmedLine.dropFirst(6))))
            } else if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
                result.append(.checkbox(checked: true, text: String(trimmedLine.dropFirst(6))))

            // Bullet list (supports indented bullets)
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
                result.append(.bullet(text: String(trimmedLine.dropFirst(2)), indent: leadingSpaces / 2))

            // Numbered list
            } else if let matchRange = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let prefix = String(line[matchRange])
                let idx = String(prefix.dropLast(2))
                let text = String(line[matchRange.upperBound...])
                result.append(.numbered(index: idx + ".", text: text))

            // Divider
            } else if line == "---" || line == "***" || line == "___" {
                result.append(.divider)

            // Blank
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(.blank)

            // Paragraph
            } else {
                result.append(.paragraph(text: line))
            }

            i += 1
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {

        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .foregroundColor(.primary)
                .padding(.top, level == 1 ? 8 : level == 2 ? 4 : 2)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.vertical, 4)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                inlineText(text)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 2)

        case .bullet(let text, let indent):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(.secondary)
                    .padding(.leading, CGFloat(indent) * 16)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .numbered(let index, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(index)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .checkbox(let checked, let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundColor(checked ? .accentColor : .secondary)
                    .font(.system(size: 15))
                inlineText(text)
                    .strikethrough(checked, color: .secondary)
                    .foregroundColor(checked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .divider:
            Divider()
                .padding(.vertical, 6)

        case .blank:
            Color.clear.frame(height: 6)

        case .paragraph(let text):
            inlineText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Renders inline text with custom markdown formatting (bold, italic, strikethrough, code, links, images).
    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        renderInlineMarkdown(raw)
    }
    
    /// Render inline markdown with actual interactive links and embedded images
    @ViewBuilder
    private func renderInlineMarkdown(_ raw: String) -> some View {
        let segments = parseInlineSegments(raw)
        
        if segments.isEmpty {
            Text("")
        } else {
            // Use HStack with wrapping for inline flow
            // For multiline content, wrap each segment in its own view
            flowLayout(segments: segments)
        }
    }
    
    @ViewBuilder
    private func flowLayout(segments: [InlineSegment]) -> some View {
        // Group consecutive text segments together, render links and images separately
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(groupSegments(segments).enumerated()), id: \.offset) { _, group in
                switch group {
                case .combinedText(let textSegments):
                    let combined = textSegments.reduce(Text("")) { result, attr in
                        result + Text(attr)
                    }
                    combined
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                case .link(let displayText, let url):
                    Link(displayText, destination: URL(string: url) ?? URL(string: "about:blank")!)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .image(let alt, let url):
                    VStack(alignment: .leading, spacing: 4) {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(height: 200)
                                    .frame(maxWidth: .infinity)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .cornerRadius(8)
                            case .failure:
                                HStack {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .foregroundColor(.red)
                                    Text("Failed to load image")
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: 100)
                                .frame(maxWidth: .infinity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        if !alt.isEmpty {
                            Text(alt)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    enum SegmentGroup {
        case combinedText([AttributedString])
        case link(displayText: String, url: String)
        case image(alt: String, url: String)
    }
    
    /// Group consecutive text segments together
    private func groupSegments(_ segments: [InlineSegment]) -> [SegmentGroup] {
        var groups: [SegmentGroup] = []
        var currentTextSegments: [AttributedString] = []
        
        for segment in segments {
            switch segment {
            case .text(let attr):
                currentTextSegments.append(attr)
            case .link(let displayText, let url):
                if !currentTextSegments.isEmpty {
                    groups.append(.combinedText(currentTextSegments))
                    currentTextSegments = []
                }
                groups.append(.link(displayText: displayText, url: url))
            case .image(let alt, let url):
                if !currentTextSegments.isEmpty {
                    groups.append(.combinedText(currentTextSegments))
                    currentTextSegments = []
                }
                groups.append(.image(alt: alt, url: url))
            }
        }
        
        if !currentTextSegments.isEmpty {
            groups.append(.combinedText(currentTextSegments))
        }
        
        return groups
    }
    
    enum InlineSegment {
        case text(AttributedString)
        case link(displayText: String, url: String)
        case image(alt: String, url: String)
    }
    
    /// Parse inline markdown into segments (text, links, images)
    private func parseInlineSegments(_ raw: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var currentPos = raw.startIndex
        
        // First, find all links and images with their positions
        struct Match {
            let range: Range<String.Index>
            let type: MatchType
        }
        
        enum MatchType {
            case link(text: String, url: String)
            case image(alt: String, url: String)
        }
        
        var matches: [Match] = []
        
        // Find all links: [text](url)
        let linkPattern = #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern) {
            let nsString = raw as NSString
            let results = linkRegex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
            for match in results where match.numberOfRanges >= 3 {
                if let range = Range(match.range, in: raw),
                   let textRange = Range(match.range(at: 1), in: raw),
                   let urlRange = Range(match.range(at: 2), in: raw) {
                    let text = String(raw[textRange])
                    let url = String(raw[urlRange])
                    matches.append(Match(range: range, type: .link(text: text, url: url)))
                }
            }
        }
        
        // Find all images: ![alt](url)
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        if let imageRegex = try? NSRegularExpression(pattern: imagePattern) {
            let nsString = raw as NSString
            let results = imageRegex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))
            for match in results where match.numberOfRanges >= 3 {
                if let range = Range(match.range, in: raw),
                   let altRange = Range(match.range(at: 1), in: raw),
                   let urlRange = Range(match.range(at: 2), in: raw) {
                    let alt = String(raw[altRange])
                    let url = String(raw[urlRange])
                    matches.append(Match(range: range, type: .image(alt: alt, url: url)))
                }
            }
        }
        
        // Sort matches by position
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }
        
        // Build segments
        for match in matches {
            // Add text before this match
            if currentPos < match.range.lowerBound {
                let textPart = String(raw[currentPos..<match.range.lowerBound])
                if !textPart.isEmpty {
                    segments.append(.text(parseTextMarkdown(textPart)))
                }
            }
            
            // Add the match
            switch match.type {
            case .link(let text, let url):
                segments.append(.link(displayText: text, url: url))
            case .image(let alt, let url):
                segments.append(.image(alt: alt, url: url))
            }
            
            currentPos = match.range.upperBound
        }
        
        // Add remaining text
        if currentPos < raw.endIndex {
            let textPart = String(raw[currentPos..<raw.endIndex])
            if !textPart.isEmpty {
                segments.append(.text(parseTextMarkdown(textPart)))
            }
        }
        
        return segments
    }
    
    /// Parse text markdown (bold, italic, strikethrough, code) to AttributedString
    /// This is used for text segments that don't contain links or images
    /// In preview mode, markers are completely removed
    private func parseTextMarkdown(_ raw: String) -> AttributedString {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)

        func boldItalicFont() -> UIFont {
            let traits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
            let desc = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        func boldFont() -> UIFont {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        func italicFont() -> UIFont {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            return UIFont(descriptor: desc, size: baseFont.pointSize)
        }
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)

        // Process markdown by removing markers and applying formatting
        var result = raw
        var ranges: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        
        // Helper to process a markdown pattern and collect formatted ranges
        func processPattern(open: String, close: String, attrs: [NSAttributedString.Key: Any]) {
            func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
            let pattern = "\(esc(open))(.+?)\(esc(close))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
            
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range
                let contentRange = match.range(at: 1)
                
                guard let fullSwiftRange = Range(fullRange, in: result),
                      let contentSwiftRange = Range(contentRange, in: result) else { continue }
                
                let content = String(result[contentSwiftRange])
                
                // Calculate new position after removing markers
                let openLen = (open as NSString).length
                let newStart = fullRange.location - offset
                let newRange = NSRange(location: newStart, length: content.count)
                
                // Store the attributes to apply later
                ranges.append((range: newRange, attrs: attrs))
                
                // Remove the markdown markers from the string
                result.replaceSubrange(fullSwiftRange, with: content)
                offset += openLen + (close as NSString).length
            }
        }
        
        // Process in longest-first order so ***x*** is caught before **x** or *x*
        processPattern(open: "***", close: "***", attrs: [.font: boldItalicFont()])
        processPattern(open: "___", close: "___", attrs: [.font: boldItalicFont()])
        processPattern(open: "**", close: "**", attrs: [.font: boldFont()])
        processPattern(open: "__", close: "__", attrs: [.font: boldFont()])
        processPattern(open: "*", close: "*", attrs: [.font: italicFont()])
        processPattern(open: "_", close: "_", attrs: [.font: italicFont()])
        processPattern(open: "~~", close: "~~", attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: UIColor.secondaryLabel
        ])
        processPattern(open: "`", close: "`", attrs: [
            .font: codeFont,
            .backgroundColor: UIColor.tertiarySystemFill,
            .foregroundColor: UIColor.systemOrange
        ])
        
        // Build the final attributed string
        let nsAttr = NSMutableAttributedString(string: result)
        for (range, attrs) in ranges.reversed() {
            if range.location >= 0 && range.location + range.length <= nsAttr.length {
                nsAttr.addAttributes(attrs, range: range)
            }
        }
        
        return AttributedString(nsAttr)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .footnote
        }
    }
}
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
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(ToolbarSettings.self) var toolbarSettings
    @Environment(\.appTheme) var theme

    // 编辑模式状态
    @State var isEditMode = false
    
    // 内容状态
    @State var content = ""
    @State var hasLoaded = false
    @State var isEditorFocused = false

    // 语音实时插入状态
    @State var contentBeforeSpeech: String = ""
    @State var contentAfterSpeech: String = ""
    @State var lastTranscriptLength: Int = 0
    @State var lastKnownCursorOffset: Int = 0

    // 弹出控制
    @State var showCamera = false
    @State var showPhotoPicker = false
    @State var activeScanMode: ScanMode?
    @State var showAudioRecorder = false
    @State var showPaintingCanvas = false
    @State var showFilePicker = false
    @State var showLocationPicker = false

    // 附件查看
    @State var selectedAttachment: AttachmentItem?
    @State var showAttachmentViewer = false
    @State var selectedAttachmentIndex: Int = 0
    
    // 附件显示模式
    enum AttachmentDisplayMode {
        case grid
        case fullSize
    }
    @State var attachmentDisplayMode: AttachmentDisplayMode = .grid

    // 编辑模式下附件栏收起状态
    @State var isAttachmentBarCollapsed = false

    // 语音输入
    @State var speechRecognizer = SpeechRecognizer()

    // 编辑器焦点
    @FocusState var editorFocused: Bool

    // 撤销/重做管理器
    @StateObject var undoRedoManager = UndoRedoManager()
    
    // 编辑内容追踪
    @State var previousContent = ""
    @State var saveTask: Task<Void, Never>?
    @State var previousAttachmentIDs: Set<UUID> = []
    @State var isPerformingUndoRedo = false
    
    // 标签管理
    @State var showTagManagement = false

    // 浮动上下文菜单
    @State var showFloatingMenu = false
    @State var floatingMenuHasSelection = false
    @State var floatingMenuIsTodoLine = false
    @State var floatingMenuIsTodoChecked = false
    @State var floatingMenuPosition: CGPoint = .zero

    // 附件插入菜单
    @State var attachmentInsertMenuID: UUID? = nil
    @State var attachmentInsertMenuAnchor: CGPoint = .zero
    
    // 格式工具栏展开状态
    @State var showExpandedFormatBar = false
    var micBottomPadding: CGFloat {
        var h: CGFloat = 44
        if showExpandedFormatBar && isMarkdownToolbarEnabled {
            h += 1 + 36 + 1 + 36
        }
        return h
    }
    
    // 当前行待办状态
    @State var currentLineIsTodo = false
    @State var currentLineIsTodoCouldBeChecked = false
    @State var todoToggleButtonPressed = false

    // Markdown 编辑器协调器
    @State var markdownCoordinator: MarkdownTextView.Coordinator?
    @State var shouldAutoFocus = false

    // 编辑状态追踪
    @State var wasEdited = false
    @State var initialContent = ""
    @State var initialAttachmentCount = 0
    @State var initialTagIDs: Set<UUID> = []
    @State var deletedAttachmentIDs: Set<UUID> = []

    // 语音输入拖拽状态
    @State var voiceDragOffset: CGFloat = 0
    @State var isVoiceButtonPressed = false
    @State var shouldCancelVoiceInput = false
    
    // 删除确认
    @State var showDeleteConfirmation = false
    
    // 删除中标记
    @State var isDeleting = false

    // 视图尺寸（替代 UIScreen.main.bounds）
    @State var viewSize: CGSize = .zero

    // 导出
    @State var showExportPicker = false
    @State var isExporting = false
    @State var exportFileURL: URL? = nil
    @State var showShareSheet = false
    @State var exportError: String? = nil
    @State var showExportError = false

    enum ScanMode: String, Identifiable {
        case textExtraction
        case documentScan
        var id: String { rawValue }
    }

    enum TextFormat {
        case bold, italic
    }

    // MARK: - Computed

    var currentAttachments: [AttachmentItem] {
        noteStore.getAttachments(for: note)
            .filter { !deletedAttachmentIDs.contains($0.id) }
    }

    var floatingMenuAnchor: CGPoint {
        let margin: CGFloat = 16
        let safeTop: CGFloat = 60
        let x = viewSize.width / 2
        let y = safeTop + margin + 160
        return CGPoint(x: x, y: y)
    }

    // MARK: - Body

    var body: some View {
        applySheets(to: baseView)
    }

    @ViewBuilder
    private func applySheets<V: View>(to content: V) -> some View {
        content
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
                isDeleting = true
                undoRedoManager.clear()
                note.undoRedoHistoryData = nil
                noteStore.softDeleteNote(note)
                dismiss()
            }
        } message: {
            Text("确定要删除这条记录吗？")
        }
        .confirmationDialog("选择导出格式", isPresented: $showExportPicker, titleVisibility: .visible) {
            Button("PDF") { triggerExport(format: .pdf) }
            Button("纯文本（.txt）") { triggerExport(format: .txt) }
            Button("Markdown（.md）") { triggerExport(format: .markdown) }
            Button("ZIP 归档（含附件）") { triggerExport(format: .zip) }
            Button("取消", role: .cancel) { }
        }
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
        .alert("导出失败", isPresented: $showExportError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(exportError ?? "未知错误")
        }
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

    private var baseView: some View {
        mainZStackContent
        .background(theme.colors.background.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isEditMode {
                    Button {
                        performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("撤销")
                    .disabled(!undoRedoManager.canUndo)

                    Button {
                        performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("重做")
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
                    .accessibilityLabel("更多操作")

                    Button {
                        exitEditMode()
                    } label: {
                        Image(systemName: (undoRedoManager.canUndo || undoRedoManager.canRedo) ? "checkmark" : "eyes")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("完成")
                } else {
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
                    .accessibilityLabel("更多操作")

                    Button {
                        enterEditMode()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("编辑")
                }
            }
        }
        .onAppear { loadContent() }
        .onDisappear { cleanupOnExit() }
        .onChange(of: content) { 
            guard isEditMode else { return }
            wasEdited = true
            if content != previousContent && !isPerformingUndoRedo {
                undoRedoManager.recordAction(.textChange(previousText: previousContent, newText: content))
                previousContent = content
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled {
                        await MainActor.run {
                            saveContentInEditMode()
                        }
                    }
                }
            }
        }
        .onChange(of: currentAttachments.count) {
            guard isEditMode else { return }
            wasEdited = true
        }
        .onChange(of: note.tags) {
            guard isEditMode else { return }
            wasEdited = true
        }
        .onChange(of: note.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .onChange(of: isEditorFocused) { onFocusChange?(isEditorFocused) }
        .onChange(of: speechRecognizer.isRecording) {
            if !speechRecognizer.isRecording {
                finalizeSpeechInsertion()
            }
        }
        .onChange(of: isVoiceButtonPressed) {
            if !isVoiceButtonPressed {
                speechRecognizer.stopRecording()
                voiceDragOffset = 0
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active && isVoiceButtonPressed {
                isVoiceButtonPressed = false
            }
        }
    }

    private var mainZStackContent: some View {
        ZStack {
            // 主内容
            Group {
                if !isEditMode {
                    ScrollView {
                        VStack(spacing: 0) {
                            mainContentView
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        mainContentView
                    }
                }
            }
            
            // 悬浮语音按钮（底部中央）
            if isEditMode {
                ZStack(alignment: .bottom) {
                    if toolbarSettings.isVoiceInputEnabled {
                        VoiceInputOverlay(
                            transcript: speechRecognizer.currentTranscript,
                            isRecording: speechRecognizer.isRecording,
                            dragOffset: 0,
                            shouldCancel: voiceDragOffset < -80
                        )
                        .offset(y: voiceDragOffset)
                        .padding(.bottom, micBottomPadding)
                        .opacity(speechRecognizer.isRecording ? 1 : 0)
                        .scaleEffect(speechRecognizer.isRecording ? 1 : 0.5, anchor: .bottom)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: speechRecognizer.isRecording)
                        
                        floatingVoiceButton
                            .padding(.bottom, micBottomPadding)
                            .opacity(speechRecognizer.isRecording ? 0 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(true)
            }

            // 浮动上下文菜单
            if showFloatingMenu {
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

            // 附件 Markdown 插入浮层
            if let menuAttachmentID = attachmentInsertMenuID,
               let menuAttachment = currentAttachments.first(where: { $0.id == menuAttachmentID }) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            attachmentInsertMenuID = nil
                        }
                    }
                    .zIndex(20)

                Button {
                    insertAttachmentMarkdown(menuAttachment)
                    withAnimation(.easeOut(duration: 0.15)) {
                        attachmentInsertMenuID = nil
                    }
                } label: {
                    Label("插入到正文", systemImage: "text.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
                }
                .fixedSize()
                .position(attachmentInsertMenuAnchor)
                .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                .zIndex(21)
            }
        }
        .coordinateSpace(name: "noteRoot")
    }

    // MARK: - 主内容视图
    
    private var mainContentView: some View {
        Group {
            if !isEditMode && onPublish == nil {
                timeInfoSection
            }

            if !isEditMode && !note.tags.isEmpty {
                tagSection
                Divider()
            }
            
            textEditorSection
            
            if !currentAttachments.isEmpty {
                Spacer()
                    .frame(height: 16)
            }

            if !currentAttachments.isEmpty {
                Divider()
                attachmentStripSection
            }

            if isEditMode && onPublish == nil {
                timeInfoSection
            }
            
            if isEditMode {
                Divider()
                bottomToolbar
            }

            if isEditMode && showExpandedFormatBar && isMarkdownToolbarEnabled {
                Divider()
                expandedFormatToolbar
            }
        }
    }
    
    // MARK: - 标签区域
    
    private var tagSection: some View {
        HStack(spacing: 4) {
            ForEach(note.tags) { tag in
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                        .font(.caption2)
                        .accessibilityHidden(true)
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
                            updateCurrentLineTodoStatus()
                        },
                        onCursorLineChanged: {
                            updateCurrentLineTodoStatus()
                            if let coord = markdownCoordinator {
                                lastKnownCursorOffset = coord.cursorOffset
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    if content.isEmpty && !speechRecognizer.isRecording && !isEditorFocused {
                        HStack {
                            Text("开始输入...")
                                .foregroundColor(Color(.placeholderText))
                                .padding(.leading, 21)
                                .padding(.trailing, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                if content.isEmpty {
                    Text("暂无内容")
                        .foregroundColor(Color(.placeholderText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            enterEditMode()
                        }
                } else {
                    MarkdownRenderView(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            enterEditMode()
                        }
                }
            }
        }
    }

    // MARK: - 时间信息
    
    var timeInfoSection: some View {
        HStack {
            Spacer()
            Text(note.createdAt.formattedFull)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

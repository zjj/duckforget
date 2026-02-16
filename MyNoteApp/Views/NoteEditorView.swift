import AVFoundation
import SwiftUI
import CoreLocation

/// 备忘录编辑器 - 支持文字输入、语音转文字、附件管理
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
    @State private var showDocumentScanner = false
    @State private var showAudioRecorder = false
    @State private var showPaintingCanvas = false
    @State private var showFilePicker = false
    @State private var showLocationPicker = false
    @State private var scanMode = ScanMode.document

    // 附件查看
    @State private var selectedAttachment: AttachmentItem?

    // 语音输入
    @StateObject private var speechRecognizer = SpeechRecognizer()

    // 文本视图 coordinator 引用
    @State private var textViewCoordinator: CursorTrackingTextView.Coordinator?

    // 撤销/重做状态
    @State private var canUndo = false
    @State private var canRedo = false

    // 导出
    @State private var showExport = false

    // 富文本工具栏
    @State private var showRichTextBar = false

    // 编辑状态追踪
    @State private var wasEdited = false
    @State private var hasPublished = false // 标记是否已点击发布按钮保存
    
    // 语音输入拖拽状态
    @State private var voiceDragOffset: CGFloat = 0
    @State private var isVoiceButtonPressed = false
    @State private var shouldCancelVoiceInput = false

    enum ScanMode { case text, document }

    /// 富文本格式类型
    enum TextFormat {
        case bold, italic
    }

    // MARK: - Computed

    private var currentAttachments: [AttachmentItem] {
        noteStore.getAttachments(for: note)
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
                    
                    if onPublish != nil {
                        Button {
                            performPublish()
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.attachments.isEmpty)
                    } else {
                        Menu {
                            Button {
                                showExport = true
                            } label: {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                noteStore.softDeleteNote(note)
                                dismiss()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                        }
                    }
                }
            }
        }
        .onAppear { loadContent() }
        .onDisappear { 
            // 无论嵌入与否，都需要清理逻辑（特别是针对 temporary note 的删除）
            cleanupOnExit() 
        }
        .onChange(of: content) { saveContent() }
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
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerView { images in handleScannedImages(images) }
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
        .sheet(isPresented: $showExport) {
            ExportSheet(note: note)
                .environment(noteStore)
        }
    }

    // MARK: - 内嵌工具栏（fullPage 组件顶部）

    /// 当 NoteEditorView 嵌入 dashboard 且 nav bar 不可见时，
    /// 在视图内部顶端渲染 undo/redo/发布 按钮
    private var embeddedToolbar: some View {
        HStack(spacing: 16) {
            Text("新建备忘录")
                .font(.headline)
            
            Spacer()
            
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
                    AttachmentThumbnailView(attachment: attachment)
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

    // MARK: - 底部工具栏（展开式附件选项）

    private var bottomToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(toolbarSettings.items) { item in
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
                scanMode = .text
                showDocumentScanner = true
            case .scanDocument:
                scanMode = .document
                showDocumentScanner = true
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
        cursorPosition = (content as NSString).length

        // 清除初始加载产生的 undo 栈，确保新笔记无法 undo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textViewCoordinator?.clearUndoStack()
        }

        hasLoaded = true
    }

    private func cleanupOnExit() {
        // 如果是新建笔记模式（onPublish != nil）
        if onPublish != nil {
            // 如果已点击发布，则不删除（已在 performPublish 中更新）
            // 如果未点击发布，则视为因退出（如切换页面）而取消，需要删除临时笔记
            if !hasPublished {
                noteStore.permanentlyDeleteNote(note)
            }
            return
        }

        // 保存最终内容
        saveContent()
        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        // 如果备忘录为空（无内容且无附件），则直接删除，不保留空记录
        // 无论是否编辑过（wasEdited），只要最终结果为空就不保存
        let isEmpty = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNoAttachments = note.attachments.isEmpty

        // 仅在非发布模式下检查空内容删除
        // 发布模式下，performPublish 已经保存并更新了内容
        if isEmpty && hasNoAttachments {
            noteStore.permanentlyDeleteNote(note)
        }
    }

    private func performPublish() {
        // 标记已发布，避免 cleanupOnExit 自动删除
        hasPublished = true
        
        // 强制保存内容
        note.content = content
        
        // 只要内容不为空或者有附件，就进行保存
        if !note.content.isEmpty || !note.attachments.isEmpty {
            noteStore.updateNote(note)
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        onPublish?()
    }

    private func saveContent() {
        // 如果正在录音，跳过自动保存（等待最终确认）
        guard !speechRecognizer.isRecording else { return }
        
        // 如果是新建笔记模式（onPublish != nil），不进行自动保存
        // 但需要更新 content 状态以便 performPublish 时获取最新数据
        // (注：performPublish 直接使用 @State content，所以这里不需要特别处理)
        if onPublish != nil { return }
        
        guard note.content != content else { return }
        wasEdited = true
        note.content = content
        noteStore.updateNote(note)
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
                
                // 手动触发保存（因为 saveContent 在录音时被阻止了）
                wasEdited = true
                note.content = content
                noteStore.updateNote(note)
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

    private func handleScannedImages(_ images: [UIImage]) {
        if scanMode == .text {
            TextRecognizer.recognizeText(from: images) { text in
                guard !text.isEmpty else { return }
                if !content.isEmpty { content += "\n" }
                content += text
            }
        } else {
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
                fileExtension: url.pathExtension
            )
        }
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
            fileExtension: "json"
        )
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
            fileExtension: "jpg"
        )
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
            fileExtension: ext
        )
    }

    /// 从视频生成缩略图
    static func generateVideoThumbnail(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
        } catch {
            return nil
        }
    }
}


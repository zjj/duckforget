import AVFoundation
import SwiftUI

/// 备忘录编辑器 - 支持文字输入、语音转文字、附件管理
struct NoteEditorView: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

                Menu {
                    Button {
                        noteStore.togglePin(note)
                    } label: {
                        Label(
                            note.isPinned ? "取消置顶" : "置顶",
                            systemImage: note.isPinned ? "pin.slash" : "pin"
                        )
                    }
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
        .onAppear { loadContent() }
        .onDisappear { cleanupOnExit() }
        .onChange(of: content) { saveContent() }
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
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation {
                                    noteStore.deleteAttachment(attachment)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
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
                // 扫描文本
                ToolbarButton(
                    icon: "text.viewfinder",
                    label: "扫描文本"
                ) {
                    scanMode = .text
                    showDocumentScanner = true
                }
                
                // 扫描文稿
                ToolbarButton(
                    icon: "doc.viewfinder",
                    label: "扫描文稿"
                ) {
                    scanMode = .document
                    showDocumentScanner = true
                }
                
                // 拍照或录像
                ToolbarButton(
                    icon: "camera",
                    label: "拍照录像"
                ) {
                    showCamera = true
                }
                
                // 选取照片或视频
                ToolbarButton(
                    icon: "photo.on.rectangle",
                    label: "照片视频"
                ) {
                    showPhotoPicker = true
                }
                
                // 录音
                ToolbarButton(
                    icon: "waveform",
                    label: "录音"
                ) {
                    showAudioRecorder = true
                }
                
                // 涂鸦
                ToolbarButton(
                    icon: "pencil.tip.crop.circle",
                    label: "涂鸦"
                ) {
                    showPaintingCanvas = true
                }
                
                // 附件文件
                ToolbarButton(
                    icon: "folder",
                    label: "附件"
                ) {
                    showFilePicker = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - 工具栏按钮组件
    
    private struct ToolbarButton: View {
        let icon: String
        let label: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                        .frame(width: 44, height: 44)
                    
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
        // 保存最终内容
        saveContent()
        // 停止语音输入
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        // 仅删除从未被编辑过的空笔记
        let isEmpty = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNoAttachments = note.attachments.isEmpty

        if !wasEdited && isEmpty && hasNoAttachments {
            noteStore.permanentlyDeleteNote(note)
        }
    }

    private func saveContent() {
        // 如果正在录音，跳过自动保存（等待最终确认）
        guard !speechRecognizer.isRecording else { return }
        
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

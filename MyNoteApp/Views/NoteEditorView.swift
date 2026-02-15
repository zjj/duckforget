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
        VStack(spacing: 0) {
            // 文本编辑区
            textEditorSection

            // 语音输入指示器
            if speechRecognizer.isRecording {
                voiceInputIndicator
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

            // 底部工具栏（仿 Apple Notes）
            bottomToolbar
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
        .onChange(of: speechRecognizer.currentTranscript) {
            handleRealtimeTranscript()
        }
        .onChange(of: speechRecognizer.isRecording) {
            if !speechRecognizer.isRecording {
                finalizeSpeechInsertion()
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

    // MARK: - 语音输入指示器
    private var voiceInputIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundColor(.green)
                .font(.subheadline)

            Text(
                speechRecognizer.currentTranscript.isEmpty
                    ? "正在聆听..."
                    : "转写中"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray6))
        )
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

    // MARK: - 底部工具栏（仿 Apple Notes）

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // 附件弹出菜单（+ 按钮）
            Menu {
                Button {
                    scanMode = .text
                    showDocumentScanner = true
                } label: {
                    Label("扫描文本", systemImage: "text.viewfinder")
                }

                Button {
                    scanMode = .document
                    showDocumentScanner = true
                } label: {
                    Label("扫描文稿", systemImage: "doc.viewfinder")
                }

                Button {
                    showCamera = true
                } label: {
                    Label("拍照或录像", systemImage: "camera")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("选取照片或视频", systemImage: "photo.on.rectangle")
                }

                Button {
                    showAudioRecorder = true
                } label: {
                    Label("录音", systemImage: "waveform")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("附件文件", systemImage: "folder")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // 语音输入按钮
            Button {
                toggleVoiceInput()
            } label: {
                Image(systemName: speechRecognizer.isRecording ? "waveform.path" : "mic")
                .font(.system(size: 48))
                .foregroundColor( speechRecognizer.isRecording ? .green : .accentColor)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
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
        guard note.content != content else { return }
        wasEdited = true
        note.content = content
        noteStore.updateNote(note)
    }

    // MARK: - 语音输入

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
        let finalTranscript = speechRecognizer.currentTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if finalTranscript.isEmpty {
            // 没有识别到内容，恢复原文
            content = contentBeforeSpeech + contentAfterSpeech
        } else {
            // 最终内容已经在 handleRealtimeTranscript 中设置好了
            // 确保最终版本正确
            content = contentBeforeSpeech + finalTranscript + contentAfterSpeech
        }

        speechRecognizer.currentTranscript = ""
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

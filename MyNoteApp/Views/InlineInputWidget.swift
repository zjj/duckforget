import SwiftUI
import UIKit
import SwiftData
import CoreLocation
import AVFoundation

/// 快捷输入组件 - 直接在 Dashboard 内输入文字并保存为记录，无需跳转页面
/// 右上角展开按钮可跳转到完整的富文本编辑器（支持附件等）
struct InlineInputWidget: View {
    let size: WidgetSize
    var onFocused: (() -> Void)? = nil
    var onVoicePressChanged: ((Bool) -> Void)? = nil
    var onRecordingPressChanged: ((Bool) -> Void)? = nil
    @Environment(NoteStore.self) var noteStore
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var inputText = ""
    @State private var showSavedFeedback = false
    @State private var feedbackTask: Task<Void, Never>?
    @State private var fullEditorRequest: FullEditorRequest? = nil
    @State private var inputMode: InputMode = .voice
    @State private var voiceState: VoiceState = .idle
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var audioRecorder = AudioRecorderService()
    @State private var voiceBaseText = ""
    @State private var didRequestKeyboardFromUserTap = false
    @State private var isVoicePressing = false
    @State private var voiceDragOffset: CGFloat = 0
    @State private var shouldCancelVoiceCapture = false
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var isProcessingDraft = false
    @StateObject private var pendingAudioPlayer = AudioPlayerModel()
    @State private var activePreviewAudioID: UUID?
    @FocusState private var isFocused: Bool

    private enum InputMode {
        case voice
        case keyboard
    }

    private enum VoiceState {
        case idle
        case recording
        case transcribing
    }

    private struct FullEditorRequest: Identifiable {
        let id = UUID()
        let content: String
        let existingNote: NoteItem?
    }

    private struct PendingAttachment: Identifiable {
        enum Payload {
            case image(UIImage)
            case video(URL)
            case file(URL)
            case audio(URL)
            case location(CLLocationCoordinate2D, UIImage)
        }

        let id = UUID()
        let type: AttachmentType
        let displayName: String
        let previewImage: UIImage?
        let duration: TimeInterval? = nil
        let payload: Payload
    }

    private let bottomControlHeight: CGFloat = 42

    private var trimmedInputText: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasDraftContent: Bool {
        !trimmedInputText.isEmpty || !pendingAttachments.isEmpty
    }

    private var isRecordingAudioAttachment: Bool {
        audioRecorder.isRecording
    }

    private var headerStatusText: String {
        if inputMode == .keyboard {
            return isFocused ? "正在输入" : "键盘输入"
        }
        if let errorMessage = speechRecognizer.errorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return errorMessage
        }
        if isRecordingAudioAttachment {
            return "正在录音附件"
        }
        if shouldCancelVoiceCapture {
            return "松开取消"
        }
        switch voiceState {
        case .idle:
            return ""
        case .recording:
            return "正在录音，上滑取消"
        case .transcribing:
            return "正在转文字"
        }
    }

    private var controlText: String {
        inputMode == .keyboard ? "键盘" : "按住说话"
    }

    private var headerStatusIcon: String {
        if let errorMessage = speechRecognizer.errorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "exclamationmark.circle.fill"
        }
        if isRecordingAudioAttachment {
            return "waveform.circle.fill"
        }
        if inputMode == .keyboard {
            return "keyboard"
        }
        if shouldCancelVoiceCapture {
            return "xmark.circle.fill"
        }
        switch voiceState {
        case .idle:
            return "mic.fill"
        case .recording:
            return "waveform"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        }
    }

    private var headerStatusColor: Color {
        if let errorMessage = speechRecognizer.errorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }
        if isRecordingAudioAttachment {
            return .red
        }
        if shouldCancelVoiceCapture {
            return .red
        }
        switch voiceState {
        case .idle:
            return inputMode == .keyboard ? theme.colors.accent : theme.colors.secondaryText
        case .recording, .transcribing:
            return theme.colors.accent
        }
    }

    private var headerStatusBackground: Color {
        if let errorMessage = speechRecognizer.errorMessage,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Color.red.opacity(0.1)
        }
        if isRecordingAudioAttachment {
            return Color.red.opacity(0.1)
        }
        if shouldCancelVoiceCapture {
            return Color.red.opacity(0.1)
        }
        switch voiceState {
        case .idle:
            return inputMode == .keyboard ? theme.colors.accentSoft : theme.colors.surface
        case .recording, .transcribing:
            return theme.colors.accentSoft
        }
    }

    private var currentModeIcon: String {
        if inputMode == .keyboard {
            return "keyboard"
        }
        switch voiceState {
        case .idle, .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        }
    }

    private var voiceControlForegroundColor: Color {
        if inputMode == .keyboard {
            return theme.colors.primaryText
        }

        switch voiceState {
        case .idle:
            return theme.colors.primaryText
        case .recording:
            return shouldCancelVoiceCapture ? .red : theme.colors.accent
        case .transcribing:
            return theme.colors.accent
        }
    }

    private var voiceControlBackgroundColor: Color {
        if inputMode == .keyboard {
            return theme.colors.surface
        }

        switch voiceState {
        case .idle:
            return theme.colors.surface
        case .recording:
            return shouldCancelVoiceCapture ? Color.red.opacity(0.12) : theme.colors.accentSoft.opacity(0.95)
        case .transcribing:
            return theme.colors.accent.opacity(0.12)
        }
    }

    private var voiceControlStrokeColor: Color {
        switch voiceState {
        case .idle:
            return theme.colors.border.opacity(0.25)
        case .recording:
            return shouldCancelVoiceCapture ? .red.opacity(0.5) : theme.colors.accent.opacity(0.55)
        case .transcribing:
            return theme.colors.accent.opacity(0.35)
        }
    }

    var body: some View {
        Group {
            switch size {
            case .small:
                smallLayout
            case .medium:
                mediumLayout
            case .large, .fullPage:
                largeLayout
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard focused, didRequestKeyboardFromUserTap else { return }
            didRequestKeyboardFromUserTap = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onFocused?()
            }
        }
        .onChange(of: speechRecognizer.currentTranscript) { _, transcript in
            guard voiceState == .recording else { return }
            inputText = mergedVoiceText(base: voiceBaseText, transcript: transcript)
        }
        .onChange(of: speechRecognizer.errorMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            setVoicePressing(false)
            voiceState = .idle
            inputText = voiceBaseText
        }
        .fullScreenCover(item: $fullEditorRequest) { request in
            NewNoteModalView(
                isPresented: Binding(
                    get: { fullEditorRequest != nil },
                    set: { if !$0 { fullEditorRequest = nil } }
                ),
                initialContent: request.content,
                existingNote: request.existingNote,
                deleteOnCancel: true
            )
            .onDisappear {
                if request.existingNote == nil {
                    resetComposerState()
                }
            }
        }
        .onDisappear {
            feedbackTask?.cancel()
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            }
            if audioRecorder.isRecording {
                if let url = audioRecorder.stopRecording() {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            cleanupPendingTemporaryFiles()
        }
    }

    // MARK: - Layouts

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            ZStack(alignment: .leading) {
                if inputText.isEmpty && !isFocused {
                    Text("想到什么，直接记下来...")
                        .font(Font(fontManager.bodyFont(size: 15)))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.35))
                        .allowsHitTesting(false)
                }

                TextField("", text: $inputText)
                    .font(Font(fontManager.bodyFont(size: 15)))
                    .foregroundColor(theme.colors.primaryText)
                    .focused($isFocused)
                    .onTapGesture {
                        requestKeyboardModeFromUserTap()
                    }
            }

            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            footerBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        .background(cardBackground(cornerRadius: 14))
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        .overlay(savedOverlay(cornerRadius: 14))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pendingAttachments.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasDraftContent)
    }

    private var mediumLayout: some View {
        editorLayout(fontSize: 15, cornerRadius: 16)
    }

    private var largeLayout: some View {
        editorLayout(fontSize: 16, cornerRadius: 16)
    }

    private func editorLayout(fontSize: CGFloat, cornerRadius: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            editorArea(fontSize: fontSize)

            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            footerBar
        }
        .padding(16)
        .frame(height: size.height)
        .background(cardBackground(cornerRadius: cornerRadius))
        .shadow(color: theme.colors.shadow, radius: 8, x: 0, y: 2)
        .overlay(savedOverlay(cornerRadius: cornerRadius))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pendingAttachments.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasDraftContent)
    }

    private func editorArea(fontSize: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty && !isFocused {
                Text("想到什么，直接记下来...")
                    .font(Font(fontManager.bodyFont(size: fontSize)))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.35))
                    .padding(.top, 8)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $inputText)
                .font(Font(fontManager.bodyFont(size: fontSize)))
                .foregroundColor(theme.colors.primaryText)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .focused($isFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            requestKeyboardModeFromUserTap()
        }
    }

    // MARK: - Shared Components

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .foregroundColor(theme.colors.accent)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("快捷输入")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.colors.secondaryText)
            headerStatusBadge
            Spacer()
            expandButton
        }
    }

    private var shouldShowStatusBadge: Bool {
        // 语音空闲态且无错误时不显示 badge
        if inputMode == .voice,
           voiceState == .idle,
           !isRecordingAudioAttachment,
           (speechRecognizer.errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    @ViewBuilder
    private var headerStatusBadge: some View {
        if shouldShowStatusBadge {
            HStack(spacing: 5) {
                if voiceState == .transcribing && inputMode == .voice {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(headerStatusColor)
                } else {
                    Image(systemName: headerStatusIcon)
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(headerStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(headerStatusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(headerStatusBackground, in: Capsule())
            .overlay(
                Capsule(style: .continuous)
                    .stroke(headerStatusColor.opacity(0.14), lineWidth: 0.8)
            )
            .animation(.easeInOut(duration: 0.2), value: headerStatusText)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            modeControl
            recordingButton
            Spacer(minLength: 0)
            if hasDraftContent {
                publishButton(compact: size == .small)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var modeControl: some View {
        Group {
            if inputMode == .voice {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(theme.colors.accent.opacity(voiceState == .recording ? 0.18 : 0.1))
                            .frame(width: 28, height: 28)
                            .scaleEffect(voiceState == .recording ? 1.08 : 1)

                        if voiceState == .transcribing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.colors.accent)
                        } else {
                            Image(systemName: currentModeIcon)
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    Text(controlText)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    if voiceState == .recording {
                        Circle()
                            .fill(shouldCancelVoiceCapture ? .red : theme.colors.accent)
                            .frame(width: 8, height: 8)
                            .opacity(isVoicePressing ? 1 : 0.5)
                    }
                }
                .foregroundStyle(voiceControlForegroundColor)
                .padding(.horizontal, 14)
                .frame(height: bottomControlHeight)
                .background(voiceControlBackgroundColor, in: Capsule())
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(voiceControlStrokeColor, lineWidth: voiceState == .idle ? 0.8 : 1.2)
                )
                .contentShape(Capsule())
                .shadow(
                    color: voiceState == .recording ? theme.colors.accent.opacity(0.22) : .clear,
                    radius: 10,
                    x: 0,
                    y: 4
                )
                .scaleEffect(isVoicePressing ? 1.03 : 1)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleVoiceGestureChanged(value)
                        }
                        .onEnded { _ in
                            finishVoiceCapture()
                        }
                )
            } else {
                Button {
                    switchToVoiceMode()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: currentModeIcon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(controlText)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: bottomControlHeight)
                    .background(theme.colors.surface, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: inputMode)
        .animation(.easeInOut(duration: 0.2), value: voiceState)
    }

    private var recordingButton: some View {
        Button {
            toggleAudioAttachmentRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecordingAudioAttachment ? "stop.circle.fill" : "waveform.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(isRecordingAudioAttachment ? "停止" : "录音")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isRecordingAudioAttachment ? Color.red : theme.colors.primaryText)
            .padding(.horizontal, 12)
            .frame(height: bottomControlHeight)
            .background(
                isRecordingAudioAttachment ? Color.red.opacity(0.12) : theme.colors.surface,
                in: Capsule()
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isRecordingAudioAttachment ? Color.red.opacity(0.25) : theme.colors.border.opacity(0.2),
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(voiceState == .recording || voiceState == .transcribing)
        .opacity((voiceState == .recording || voiceState == .transcribing) ? 0.5 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onRecordingPressChanged?(true)
                }
                .onEnded { _ in
                    onRecordingPressChanged?(false)
                }
        )
    }

    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 6) {
                        pendingAttachmentThumbnail(for: attachment)

                        Text(attachment.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)

                        Button {
                            removePendingAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.colors.surface, in: Capsule())
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.colors.border.opacity(0.2), lineWidth: 0.8)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func pendingAttachmentThumbnail(for attachment: PendingAttachment) -> some View {
        if let previewImage = attachment.previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.colors.accentSoft)
                    .frame(width: 22, height: 22)

                Image(systemName: attachment.type.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
        }
    }

    private var expandButton: some View {
        Button {
            openFullEditor()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .semibold))
                Text("展开")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.colors.accent.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessingDraft)
        .opacity(isProcessingDraft ? 0.6 : 1)
    }

    private func publishButton(compact: Bool) -> some View {
        Button {
            saveNote()
        } label: {
            if compact {
                Text("发布")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: bottomControlHeight)
                    .background(theme.colors.accent, in: Capsule())
            } else {
                Text("发布")
                    .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: bottomControlHeight)
                .background(theme.colors.accent, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasDraftContent || isProcessingDraft)
        .opacity((!hasDraftContent || isProcessingDraft) ? 0.6 : 1)
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.colors.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    private func savedOverlay(cornerRadius: CGFloat) -> some View {
        Group {
            if showSavedFeedback {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(theme.colors.accent)
                                .symbolRenderingMode(.hierarchical)
                            Text("已收录")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(theme.colors.primaryText)
                            Text("已同步到最近记录和日历")
                                .font(.system(size: 11))
                                .foregroundColor(theme.colors.secondaryText.opacity(0.7))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    // MARK: - Actions

    private func requestKeyboardModeFromUserTap() {
        speechRecognizer.errorMessage = nil
        didRequestKeyboardFromUserTap = true
        inputMode = .keyboard
        isFocused = true
    }

    private func switchToVoiceMode() {
        didRequestKeyboardFromUserTap = false
        inputMode = .voice
        isFocused = false
    }

    private func handleVoiceGestureChanged(_ value: DragGesture.Value) {
        guard !isRecordingAudioAttachment else { return }
        beginVoiceCaptureIfNeeded()
        guard isVoicePressing else { return }

        voiceDragOffset = min(value.translation.height, 0)
        let shouldCancel = voiceDragOffset < -70
        if shouldCancel != shouldCancelVoiceCapture {
            shouldCancelVoiceCapture = shouldCancel
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(shouldCancel ? .warning : .success)
        }
    }

    private func beginVoiceCaptureIfNeeded() {
        guard !isRecordingAudioAttachment else { return }
        guard inputMode == .voice, voiceState != .transcribing, !isProcessingDraft else { return }
        guard !isVoicePressing else { return }
        setVoicePressing(true)
        voiceDragOffset = 0
        shouldCancelVoiceCapture = false
        isFocused = false
        speechRecognizer.errorMessage = nil
        speechRecognizer.currentTranscript = ""
        voiceBaseText = inputText
        voiceState = .recording

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        speechRecognizer.startRecording()
    }

    private func finishVoiceCapture() {
        guard isVoicePressing else { return }
        setVoicePressing(false)
        let shouldCancel = shouldCancelVoiceCapture
        voiceDragOffset = 0
        shouldCancelVoiceCapture = false

        if speechRecognizer.isRecording {
            voiceState = .transcribing
            speechRecognizer.stopRecording()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                finalizeVoiceCapture(shouldCancel: shouldCancel)
            }
        } else {
            // 授权弹窗还在显示、录音尚未真正开始，取消待处理的请求
            speechRecognizer.stopRecording()
            voiceState = .idle
            inputText = voiceBaseText
        }
    }

    private func finalizeVoiceCapture(shouldCancel: Bool) {
        if shouldCancel {
            inputText = voiceBaseText
            speechRecognizer.currentTranscript = ""
            voiceBaseText = ""
            voiceState = .idle
            return
        }

        let finalTranscript = speechRecognizer.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if finalTranscript.isEmpty {
            inputText = voiceBaseText
        } else {
            inputText = mergedVoiceText(base: voiceBaseText, transcript: finalTranscript)
        }

        speechRecognizer.currentTranscript = ""
        voiceBaseText = ""
        voiceState = .idle
    }

    private func setVoicePressing(_ pressing: Bool) {
        guard isVoicePressing != pressing else { return }
        isVoicePressing = pressing
        onVoicePressChanged?(pressing)
    }

    private func appendAudioAttachment(_ url: URL) {
        speechRecognizer.errorMessage = nil
        pendingAttachments.append(
            PendingAttachment(
                type: .audio,
                displayName: "录音",
                previewImage: nil,
                payload: .audio(url)
            )
        )
    }

    private func removePendingAttachment(_ id: UUID) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = pendingAttachments.remove(at: index)
        cleanupTemporaryResource(for: attachment)
    }

    private func toggleAudioAttachmentRecording() {
        guard !isProcessingDraft else { return }

        if isRecordingAudioAttachment {
            if let url = audioRecorder.stopRecording() {
                appendAudioAttachment(url)
            }
            return
        }

        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            setVoicePressing(false)
            voiceState = .idle
            shouldCancelVoiceCapture = false
            voiceDragOffset = 0
        }

        _ = audioRecorder.startRecording()
    }

    private func saveNote() {
        guard hasDraftContent, !isProcessingDraft else { return }
        isProcessingDraft = true
        isFocused = false

        Task { @MainActor in
            let note = noteStore.createNote()
            note.content = trimmedInputText
            let savedAttachmentCount = await persistPendingAttachments(to: note)

            guard !trimmedInputText.isEmpty || savedAttachmentCount > 0 else {
                noteStore.modelContext.delete(note)
                isProcessingDraft = false
                return
            }

            noteStore.updateNote(note)
            showSavedSuccessAndReset()
        }
    }

    private func openFullEditor() {
        guard !isProcessingDraft else { return }
        isFocused = false

        guard !pendingAttachments.isEmpty else {
            fullEditorRequest = FullEditorRequest(content: inputText, existingNote: nil)
            return
        }

        isProcessingDraft = true

        Task { @MainActor in
            let note = noteStore.createNote()
            note.content = inputText
            let savedAttachmentCount = await persistPendingAttachments(to: note)

            guard !trimmedInputText.isEmpty || savedAttachmentCount > 0 else {
                noteStore.modelContext.delete(note)
                isProcessingDraft = false
                fullEditorRequest = FullEditorRequest(content: inputText, existingNote: nil)
                return
            }

            noteStore.updateNote(note)
            resetComposerState()
            isProcessingDraft = false
            fullEditorRequest = FullEditorRequest(content: "", existingNote: note)
        }
    }

    private func showSavedSuccessAndReset() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showSavedFeedback = true
        }

        resetComposerState(clearFeedback: false)
        isProcessingDraft = false
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showSavedFeedback = false
            }
        }
    }

    private func resetComposerState(clearFeedback: Bool = true) {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        if audioRecorder.isRecording {
            if let url = audioRecorder.stopRecording() {
                try? FileManager.default.removeItem(at: url)
            }
        }
        cleanupPendingTemporaryFiles()
        inputText = ""
        pendingAttachments = []
        voiceBaseText = ""
        speechRecognizer.currentTranscript = ""
        speechRecognizer.errorMessage = nil
        inputMode = .voice
        voiceState = .idle
        voiceDragOffset = 0
        shouldCancelVoiceCapture = false
        setVoicePressing(false)
        didRequestKeyboardFromUserTap = false
        isFocused = false
        if clearFeedback {
            showSavedFeedback = false
            isProcessingDraft = false
        }
    }

    private func cleanupPendingTemporaryFiles() {
        pendingAttachments.forEach { cleanupTemporaryResource(for: $0) }
    }

    private func cleanupTemporaryResource(for attachment: PendingAttachment) {
        switch attachment.payload {
        case .video(let url), .audio(let url):
            try? FileManager.default.removeItem(at: url)
        case .image, .file, .location:
            break
        }
    }

    private func mergedVoiceText(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }

        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty else { return cleanedTranscript }

        if base.hasSuffix("\n") || base.hasSuffix(" ") {
            return base + cleanedTranscript
        }
        return base + "\n" + cleanedTranscript
    }

    private func persistPendingAttachments(to note: NoteItem) async -> Int {
        var savedCount = 0

        for attachment in pendingAttachments {
            switch attachment.payload {
            case .image(let image):
                if saveImageAttachment(image, to: note, type: attachment.type) != nil {
                    savedCount += 1
                }
            case .video(let url):
                if await saveVideoAttachment(url, to: note) != nil {
                    savedCount += 1
                }
                try? FileManager.default.removeItem(at: url)
            case .file(let url):
                if await saveFileAttachment(url, to: note) != nil {
                    savedCount += 1
                }
            case .audio(let url):
                if await saveAudioAttachment(url, to: note) != nil {
                    savedCount += 1
                }
                try? FileManager.default.removeItem(at: url)
            case .location(let coordinate, let snapshot):
                if saveLocationAttachment(coordinate: coordinate, snapshot: snapshot, to: note) != nil {
                    savedCount += 1
                }
            }
        }

        return savedCount
    }

    private func saveImageAttachment(_ image: UIImage, to note: NoteItem, type: AttachmentType) -> AttachmentItem? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
        let thumbnailData = thumbnailJPEGData(for: image)
        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: type,
            data: imageData,
            thumbnailData: thumbnailData,
            fileExtension: "jpg",
            shouldSave: false
        )

        if let attachment, type == .photo || type == .scannedDocument {
            let store = noteStore
            TextRecognizer.recognizeText(from: image) { text in
                guard !text.isEmpty else { return }
                store.applyRecognitionMeta(to: attachment, text: text)
            }
        }

        return attachment
    }

    private func saveVideoAttachment(_ url: URL, to note: NoteItem) async -> AttachmentItem? {
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data else { return nil }
        let frame = await NoteView.generateVideoFirstFrame(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        return noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .video,
            data: data,
            thumbnailData: frame.thumbnailData,
            fileExtension: ext,
            shouldSave: false
        )
    }

    private func saveFileAttachment(_ url: URL, to note: NoteItem) async -> AttachmentItem? {
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data else { return nil }
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension

        return noteStore.addAttachment(
            to: note,
            type: .file,
            data: data,
            fileExtension: ext,
            shouldSave: false
        )
    }

    private func saveAudioAttachment(_ url: URL, to note: NoteItem) async -> AttachmentItem? {
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data else { return nil }

        let attachment = noteStore.addAttachment(
            to: note,
            type: .audio,
            data: data,
            fileExtension: "m4a",
            shouldSave: false
        )

        if let attachment {
            let savedURL = noteStore.attachmentURL(for: attachment)
            let store = noteStore
            SpeechRecognizer.transcribeFile(at: savedURL) { text in
                guard !text.isEmpty else { return }
                store.applyRecognitionMeta(to: attachment, text: text)
            }
        }

        return attachment
    }

    private func saveLocationAttachment(
        coordinate: CLLocationCoordinate2D,
        snapshot: UIImage,
        to note: NoteItem
    ) -> AttachmentItem? {
        let locationData: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: locationData),
              let snapshotData = snapshot.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        let attachment = noteStore.addAttachmentWithThumbnail(
            to: note,
            type: .location,
            data: jsonData,
            thumbnailData: snapshotData,
            fileExtension: "json",
            shouldSave: false
        )

        if let attachment {
            applyGeocodedAddress(to: attachment, coordinate: coordinate)
        }

        return attachment
    }

    private func applyGeocodedAddress(to attachment: AttachmentItem, coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let store = noteStore

        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if error != nil {
                DispatchQueue.main.async {
                    store.applyLocation(to: attachment, address: "未知位置")
                }
                return
            }

            guard let placemark = placemarks?.first else {
                DispatchQueue.main.async {
                    store.applyLocation(to: attachment, address: "未知位置")
                }
                return
            }

            let parts = [
                placemark.country,
                placemark.administrativeArea,
                placemark.locality,
                placemark.subLocality,
                placemark.thoroughfare,
                placemark.subThoroughfare,
                placemark.name
            ].compactMap { $0 }

            let address = parts.joined(separator: "\t")
            DispatchQueue.main.async {
                let finalAddress = address.isEmpty ? "未知位置" : address
                store.applyLocation(to: attachment, address: finalAddress)
            }
        }
    }

    private func thumbnailJPEGData(for image: UIImage) -> Data? {
        let thumbSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbImage = renderer.image { _ in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = max(thumbSize.width / size.width, thumbSize.height / size.height)
            let scaledWidth = size.width * scale
            let scaledHeight = size.height * scale
            let x = (thumbSize.width - scaledWidth) / 2
            let y = (thumbSize.height - scaledHeight) / 2
            image.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
        }
        return thumbImage.jpegData(compressionQuality: 0.6)
    }
}

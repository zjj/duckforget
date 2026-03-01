import SwiftUI

/// 录音界面 - 录制音频并保存为附件
struct AudioRecorderSheet: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var recorder = AudioRecorderService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // 录音可视化
                recordingVisualization

                Spacer()
                    .frame(height: 32)

                // 录音时长
                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(size: 52, weight: .light, design: .monospaced))
                    .foregroundColor(recorder.isRecording ? .primary : .secondary)
                    .monospacedDigit()

                Spacer()

                // 控制按钮
                controlButtons

                Spacer()
                    .frame(height: 50)
            }
            .navigationTitle("录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        _ = recorder.stopRecording()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("取消录音")
                }
            }
        }
    }

    // MARK: - 录音可视化
    private var recordingVisualization: some View {
        ZStack {
            // 外圈
            Circle()
                .fill(
                    recorder.isRecording
                        ? Color.red.opacity(0.08)
                        : theme.colors.cardSecondary
                )
                .frame(width: 160, height: 160)

            // 脉冲动画圈
            if recorder.isRecording {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .scaleEffect(recorder.isRecording ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: recorder.isRecording
                    )
            }

            // 图标
            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(recorder.isRecording ? .red : Color(.systemGray2))
                .accessibilityLabel(recorder.isRecording ? "录音中" : "待录音")
        }
    }

    // MARK: - 控制按钮

    private var controlButtons: some View {
        HStack(spacing: 50) {
            if recorder.isRecording {
                // 停止并保存
                Button {
                    if let url = recorder.stopRecording() {
                        saveRecording(from: url)
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 72, height: 72)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
            } else {
                // 开始录音
                Button {
                    _ = recorder.startRecording()
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    private func saveRecording(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            dismiss()
            return
        }

        let attachment = noteStore.addAttachment(
            to: note,
            type: .audio,
            data: data,
            fileExtension: "m4a",
            shouldSave: false // 由父容器 NoteView 的 Checkmark 统一保存
        )

        // 清理临时文件
        try? FileManager.default.removeItem(at: url)

        // 异步转录录音，结果写入 recognitionMeta 并重建 forSearch
        if let attachment {
            let savedURL = noteStore.attachmentURL(for: attachment)
            let store = noteStore
            SpeechRecognizer.transcribeFile(at: savedURL) { text in
                guard !text.isEmpty else { return }
                store.applyRecognitionMeta(to: attachment, text: text)
            }
        }

        dismiss()
    }
}

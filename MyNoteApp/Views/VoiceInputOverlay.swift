import SwiftUI

/// 语音输入悬浮面板 - 长按麦克风时显示在屏幕中央偏上，远离手指
struct VoiceInputOverlay: View {
    let transcript: String
    let isRecording: Bool
    let dragOffset: CGFloat
    let shouldCancel: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // ── 顶部：录音状态指示 ──
            HStack(spacing: 8) {
                Circle()
                    .fill(shouldCancel ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(shouldCancel ? Color.red.opacity(0.4) : Color.green.opacity(0.4))
                            .frame(width: 16, height: 16)
                            .scaleEffect(isRecording ? 1.2 : 0.8)
                            .opacity(isRecording ? 0.6 : 0)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: isRecording
                            )
                    )
                Text(shouldCancel ? "松开取消" : "正在聆听")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(shouldCancel ? .red : .primary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // ── 波形动画 ──
            WaveformAnimationView(isRecording: isRecording)
                .frame(height: 36)
                .padding(.horizontal, 24)
                .opacity(shouldCancel ? 0.3 : 1.0)

            // ── 分隔线 ──
            Divider()
                .padding(.vertical, 10)
                .padding(.horizontal, 20)

            // ── 识别的文字 ──
            ScrollView {
                Text(transcript.isEmpty ? "等待语音..." : transcript)
                    .font(.body)
                    .foregroundColor(transcript.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
            }
            .frame(minHeight: 40, maxHeight: 100)

            // ── 底部操作提示 ──
            HStack(spacing: 6) {
                Image(systemName: shouldCancel ? "xmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundColor(shouldCancel ? .red : .secondary)
                Text(shouldCancel ? "松开即可取消" : "上滑取消")
                    .font(.caption)
                    .foregroundColor(shouldCancel ? .red : .secondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(shouldCancel ? Color.red.opacity(0.08) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    shouldCancel ? Color.red.opacity(0.3) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
        .offset(y: dragOffset)
        .scaleEffect(isRecording ? 1.0 : 0.5)
        .opacity(isRecording ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: shouldCancel)
        .animation(.spring(response: 0.15, dampingFraction: 0.9), value: dragOffset)
    }
}

#Preview {
    ZStack {
        Color(.systemGray6).ignoresSafeArea()

        VStack(spacing: 60) {
            VoiceInputOverlay(
                transcript: "这是识别的文字内容，正在实时显示...",
                isRecording: true,
                dragOffset: 0,
                shouldCancel: false
            )

            VoiceInputOverlay(
                transcript: "上移可以取消录音",
                isRecording: true,
                dragOffset: 0,
                shouldCancel: true
            )
        }
        .padding()
    }
}

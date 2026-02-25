import SwiftUI

/// 语音输入悬浮窗口 - 从麦克风按钮向上延伸，包含波形、文字和操作提示
struct VoiceInputOverlay: View {
    let transcript: String
    let isRecording: Bool
    let dragOffset: CGFloat
    let shouldCancel: Bool
    @Environment(\.appTheme) private var theme
    
    var body: some View {
        VStack(spacing: 8) {
            // 主卡片：从麦克风延伸出来的悬浮窗口
            VStack(spacing: 12) {
                // 识别的文字（顶部）
                ScrollView {
                    Text(transcript.isEmpty ? "开始聆听..." : transcript)
                        .font(.body)
                        .foregroundColor(transcript.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
                .frame(minHeight: 60, maxHeight: 120)
                .padding(.top, 12)
                
                // 操作提示（中部）
                HStack(spacing: 12) {
                    Text("松开结束，上移取消")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // 波形动画（底部）
                WaveformAnimationView(isRecording: isRecording)
                    .frame(height: 30)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity) // 宽度100%
            .padding(.horizontal, 16) // 左右留边距
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(shouldCancel ? Color.red.opacity(0.1) : theme.colors.surface)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .offset(y: dragOffset)
        .scaleEffect(isRecording ? 1.0 : 0.5)
        .opacity(isRecording ? 1.0 : 0.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: shouldCancel)
        .animation(.spring(response: 0.15, dampingFraction: 0.9), value: dragOffset)
    }
}

/// 三角形形状 - 用于连接卡片和按钮
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color(.systemGray6).ignoresSafeArea()
        
        VStack(spacing: 100) {
            // 正常状态
            VStack(spacing: 8) {
                Text("正常录音状态（全宽）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    VoiceInputOverlay(
                        transcript: "这是识别的文字内容，正在实时显示...",
                        isRecording: true,
                        dragOffset: 0,
                        shouldCancel: false
                    )
                }
            }
            
            // 取消状态
            VStack(spacing: 8) {
                Text("取消状态（上移）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    VoiceInputOverlay(
                        transcript: "上移可以取消录音",
                        isRecording: true,
                        dragOffset: -100,
                        shouldCancel: true
                    )
                }
            }
        }
        .padding()
    }
}

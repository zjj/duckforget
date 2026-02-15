import SwiftUI

/// 波形动画视图 - 语音录音时的动态波形效果
struct WaveformAnimationView: View {
    let isRecording: Bool
    let barCount: Int = 5
    
    @State private var barHeights: [CGFloat] = []
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(width: 3, height: barHeights.indices.contains(index) ? barHeights[index] : 10)
                    .animation(.easeInOut(duration: 0.3), value: barHeights.indices.contains(index) ? barHeights[index] : 10)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isRecording) { 
            if isRecording {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        // 初始化高度
        barHeights = Array(repeating: 10, count: barCount)
        
        // 停止已有的定时器
        timer?.invalidate()
        
        // 创建新的定时器，每100ms更新一次波形
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation {
                barHeights = (0..<barCount).map { _ in
                    CGFloat.random(in: 8...28)
                }
            }
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        
        // 恢复到静止状态
        withAnimation {
            barHeights = Array(repeating: 10, count: barCount)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        WaveformAnimationView(isRecording: true)
        
        WaveformAnimationView(isRecording: false)
    }
    .padding()
    .background(Color(.systemBackground))
}

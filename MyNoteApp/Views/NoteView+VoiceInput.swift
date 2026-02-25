import SwiftUI

// MARK: - 语音输入

extension NoteView {

    // MARK: 悬浮语音按钮

    var floatingVoiceButton: some View {
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
        .accessibilityLabel(speechRecognizer.isRecording ? "停止语音输入" : "开始语音输入")
        .accessibilityAddTraits(.isButton)
    }
    
    var buttonColor: Color {
        if !isVoiceButtonPressed {
            return theme.colors.accent
        }
        return voiceDragOffset < -80 ? .red : .green
    }

    // MARK: 拖拽处理

    /// 处理语音按钮拖拽变化
    func handleVoiceDragChanged(_ value: DragGesture.Value) {
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
    func handleVoiceDragEnded(_ value: DragGesture.Value) {
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

    func toggleVoiceInput() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        } else {
            beginSpeechInsertion()
            speechRecognizer.startRecording()
        }
    }

    // MARK: 语音识别

    /// 开始语音输入：将内容在光标处分割为前后两段，在光标处插入
    func beginSpeechInsertion() {
        let nsContent = content as NSString
        // 优先使用实时保存的光标位置（应对按下话筒按钮导致焦点丢失的问题）
        let cursorOffset: Int
        if let coord = markdownCoordinator {
            let live = coord.cursorOffset
            // live 为 0 且内容非空时，可能是焦点干扰导致重置，改用之前保存的值
            cursorOffset = (live == 0 && nsContent.length > 0) ? min(lastKnownCursorOffset, nsContent.length) : min(live, nsContent.length)
        } else {
            cursorOffset = nsContent.length
        }
        contentBeforeSpeech = nsContent.substring(to: cursorOffset)
        contentAfterSpeech = nsContent.substring(from: cursorOffset)
        lastTranscriptLength = 0

        // 重置取消标记
        shouldCancelVoiceInput = false
    }

    /// 实时处理语音转文字：把 transcript 拼接到光标位置
    func handleRealtimeTranscript() {
        guard speechRecognizer.isRecording else { return }

        let transcript = speechRecognizer.currentTranscript
        let newContent = contentBeforeSpeech + transcript + contentAfterSpeech
        content = newContent

        lastTranscriptLength = (transcript as NSString).length
    }

    /// 语音结束：最终确认内容
    func finalizeSpeechInsertion() {
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

                // 标记已编辑（不自动保存）
                wasEdited = true

                // 将光标移动到插入文字结尾
                let cursorPosition = contentBeforeSpeech.count + finalTranscript.count
                DispatchQueue.main.async {
                    markdownCoordinator?.setCursorPosition(cursorPosition)
                }
            }
            
            speechRecognizer.currentTranscript = ""
        }
        
        // 清理临时状态
        contentBeforeSpeech = ""
        contentAfterSpeech = ""
        lastTranscriptLength = 0
    }
}

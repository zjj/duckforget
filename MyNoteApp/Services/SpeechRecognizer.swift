import Speech
import AVFoundation
import CoreLocation

/// 语音转文字服务 - 使用 Apple Speech 框架进行实时语音识别
@Observable
class SpeechRecognizer {
    var isRecording = false
    var currentTranscript = ""
    var errorMessage: String?
    
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    
    /// 标记用户是否请求了开始录音（用于处理权限请求过程中的取消操作）
    private var isStartRequested = false
    
    // MARK: - Public

    func startRecording() {
        isStartRequested = true
        currentTranscript = ""
        errorMessage = nil
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // 如果在授权过程中用户已经取消录音（例如手指松开），则停止流程
                guard self.isStartRequested else { return }
                
                switch status {
                case .authorized:
                    self.requestMicrophoneAccess()
                case .denied, .restricted:
                    self.errorMessage = "语音识别权限被拒绝，请在设置中开启"
                case .notDetermined:
                    self.errorMessage = "语音识别权限未确定"
                @unknown default:
                    self.errorMessage = "未知授权状态"
                }
            }
        }
    }
    
    func stopRecording() {
        isStartRequested = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    /// 离线转录已保存的音频文件，结果通过 completion 回调返回（主线程）
    static func transcribeFile(at url: URL, completion: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { completion("") }
                return
            }
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard let recognizer, recognizer.isAvailable else {
                DispatchQueue.main.async { completion("") }
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            recognizer.recognitionTask(with: request) { result, error in
                let text = result?.bestTranscription.formattedString ?? ""
                if result?.isFinal == true || error != nil {
                    DispatchQueue.main.async { completion(text) }
                }
            }
        }
    }
    
    // MARK: - Private
    
    private func requestMicrophoneAccess() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // 再次检查用户意图，防止授权期间用户已松手
                guard self.isStartRequested else { return }
                
                if granted {
                    self.beginRecognition()
                } else {
                    self.errorMessage = "请在设置中允许使用麦克风"
                }
            }
        }
    }
    
    private func beginRecognition() {
        // 再次确认是否应该开始（防止在异步流程中用户已取消）
        guard isStartRequested else { return }
        
        // 取消之前的任务
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 重置音频引擎以清除可能存在的无效状态
        audioEngine.reset()
        
        // 配置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "音频会话配置失败: \(error.localizedDescription)"
            return
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "无法创建识别请求"
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "语音识别服务不可用"
            return
        }
        
        // 启动识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.currentTranscript = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async {
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isRecording = false
                }
            }
        }
        
        // 安装音频输入 Tap
        let inputNode = audioEngine.inputNode
        
        // 移除可能存在的旧 Tap，防止崩溃
        inputNode.removeTap(onBus: 0)
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        var finalFormat = recordingFormat
        
        // 尝试修复无效的格式 (采样率或通道数为0)
        // 通常意味着输入节点尚未连接或音频会话未正确激活
        if finalFormat.sampleRate == 0 || finalFormat.channelCount == 0 {
            // 尝试使用默认设置
            if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) {
                finalFormat = format
            } else {
                errorMessage = "无法创建有效的音频格式"
                return
            }
        }
        
        // 最后添加异常捕获，防止极端的格式不兼容导致的崩溃
        // 尽管 AVAudioFormat 通常不抛出，但 installTap 在某些系统版本对参数校验非常严格
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: finalFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // 启动音频引擎
        audioEngine.prepare()
        do {
            // 最后再次确认意图，确保在长时间配置后用户没有取消
            guard isStartRequested else { return }
            
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "音频引擎启动失败: \(error.localizedDescription)"
        }
    }
}

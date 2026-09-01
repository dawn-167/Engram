import AVFoundation
import Speech

// MARK: - 语音识别服务（ASR）
// 用 macOS 自带 Speech 框架做英文识别，优先离线（on-device）识别，
// 替代 ChatterPal 依赖的云端 Whisper / 阿里云 ASR，无需任何 API Key。
// Services 层：只负责音频与识别，不包含任何 UI。

/// 语音识别错误（对用户友好，不暴露底层术语）
enum SpeechRecognitionError: LocalizedError {
    case notAvailable
    case notAuthorized
    case audioEngineFailure

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "当前系统不支持英文离线语音识别，可先使用跟读模式。"
        case .notAuthorized:
            return "未获得麦克风/语音识别授权，请在系统设置中允许后重试。"
        case .audioEngineFailure:
            return "麦克风启动失败，请检查音频设备后重试。"
        }
    }
}

@MainActor
protocol SpeechRecognitionServiceProtocol {
    /// 英文识别是否可用
    var isAvailable: Bool { get }
    /// 请求麦克风与语音识别授权
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)
    /// 开始录音识别
    /// - Parameters:
    ///   - onPartial: 实时部分识别结果
    ///   - onFinished: 结束时回调（识别文本 + 录音时长秒）；失败回错误
    func start(onPartial: @escaping (String) -> Void,
               onFinished: @escaping (Result<(text: String, duration: TimeInterval), SpeechRecognitionError>) -> Void) throws
    /// 停止录音，触发 onFinished
    func stop()
}

@MainActor
final class SpeechRecognitionService: SpeechRecognitionServiceProtocol {

    // MARK: - 属性

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startDate: Date?
    private var finishCallback: ((Result<(text: String, duration: TimeInterval), SpeechRecognitionError>) -> Void)?
    private var lastTranscript = ""

    var isAvailable: Bool {
        SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable == true
    }

    // MARK: - 初始化

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - 公开方法

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            DispatchQueue.main.async {
                guard speechStatus == .authorized else {
                    completion(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                    DispatchQueue.main.async { completion(micGranted) }
                }
            }
        }
    }

    func start(onPartial: @escaping (String) -> Void,
               onFinished: @escaping (Result<(text: String, duration: TimeInterval), SpeechRecognitionError>) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            onFinished(.failure(.notAvailable))
            return
        }
        // 清理上一次会话
        resetTask()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 优先离线识别，保护隐私；设备不支持时自动回退在线识别
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        self.finishCallback = onFinished
        self.lastTranscript = ""
        self.startDate = Date()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // 音频 tap 在音频线程回调，统一切回主线程访问 MainActor 隔离的状态
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            DispatchQueue.main.async { self?.request?.append(buffer) }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.lastTranscript = result.bestTranscription.formattedString
                    onPartial(self.lastTranscript)
                    if result.isFinal {
                        self.emitFinish()
                    }
                }
                // 出错且不是主动取消：以当前已识别文本收尾，避免用户卡死
                if error != nil && self.audioEngine.isRunning {
                    self.emitFinish()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            resetTask()
            throw SpeechRecognitionError.audioEngineFailure
        }
    }

    func stop() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        request?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        emitFinish()
    }

    // MARK: - 私有方法

    private func emitFinish() {
        guard let callback = finishCallback else { return }
        let duration = startDate.map { Date().timeIntervalSince($0) } ?? 0
        callback(.success((lastTranscript, duration)))
        finishCallback = nil
        resetTask()
    }

    private func resetTask() {
        if audioEngine.isRunning { audioEngine.stop() }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        task = nil
        request = nil
    }
}

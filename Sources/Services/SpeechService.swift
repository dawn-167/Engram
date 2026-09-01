import AVFoundation

// MARK: - 系统语音合成服务（TTS）
// 用 macOS 自带 AVSpeechSynthesizer 朗读英文，替代 ChatterPal 依赖的云端 Edge TTS，
// 完全离线、无需 API Key。Services 层：无 UI 依赖。所有方法约定在主线程调用。

@MainActor
protocol SpeechServiceProtocol {
    /// 是否正在朗读
    var isSpeaking: Bool { get }
    /// 朗读一段英文
    /// - Parameters:
    ///   - text: 英文文本
    ///   - rate: AVSpeechUtteranceDefaultSpeechRate 基准下的语速倍率（0.3~0.6 适合学习）
    func speak(_ text: String, rate: Float)
    /// 停止朗读
    func stop()
}

final class SpeechService: NSObject, SpeechServiceProtocol, AVSpeechSynthesizerDelegate {

    // MARK: - 属性

    // 系统合成器非 Sendable，本类约定只在主线程使用，显式标注以消除数据竞争告警
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// 优先使用的英文嗓音（系统自带），找不到则回退任意 en 嗓音
    private let preferredVoiceIdentifier = "com.apple.voice.enhanced.en-US.Samantha"

    // MARK: - 初始化

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - 公开方法

    func speak(_ text: String, rate: Float) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: preferredVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        // rate 以系统默认语速为基准换算
        utterance.rate = rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            isSpeaking = false
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - 代理回调

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}

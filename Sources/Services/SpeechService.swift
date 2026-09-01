import AVFoundation

// MARK: - 系统语音合成服务（TTS）
// 用 macOS 自带 AVSpeechSynthesizer 朗读英文，替代 ChatterPal 依赖的云端 Edge TTS，
// 完全离线、无需 API Key。Services 层：无 UI 依赖。所有方法约定在主线程调用。

@MainActor
protocol SpeechServiceProtocol {
    /// 是否正在朗读
    var isSpeaking: Bool { get }
    /// 当前选中嗓音描述
    var selectedVoiceDescription: String { get }
    /// 可用英文嗓音列表（identifier, 展示名）
    var availableVoices: [(identifier: String, label: String)] { get }
    /// 切换嗓音
    func setVoice(identifier: String)
    /// 朗读一段英文
    /// - Parameters:
    ///   - text: 英文文本
    ///   - rate: AVSpeechUtteranceDefaultSpeechRate 基准下的语速倍率（0.3~0.6 适合学习）
    ///   - locale: BCP-47 语言标签（en-US 美音 / en-GB 英音）；传空串表示不朗读（关闭发音）
    func speak(_ text: String, rate: Float, locale: String)
    /// 停止朗读
    func stop()
}

extension SpeechServiceProtocol {
    /// 便捷方法：默认美音
    func speak(_ text: String, rate: Float) {
        speak(text, rate: rate, locale: "en-US")
    }
}

final class SpeechService: NSObject, SpeechServiceProtocol, AVSpeechSynthesizerDelegate {

    // MARK: - 属性

    // 系统合成器非 Sendable，本类约定只在主线程使用，显式标注以消除数据竞争告警
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// 运行时选出的最佳英文嗓音（Premium > Enhanced > Default）
    private var bestVoice: AVSpeechSynthesisVoice?

    // MARK: - 初始化

    override init() {
        super.init()
        synthesizer.delegate = self
        bestVoice = Self.pickBestVoice()
    }

    // MARK: - 嗓音选择

    /// 枚举系统已安装的英文语音，按质量优先选出最自然的一个。
    /// 质量排序：Premium（最自然，需用户在系统设置下载）> Enhanced > Default。
    /// 语言偏好：en-US > en-GB > 其他 en。
    private static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let english = voices.filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return nil }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            let qualityScore: Int
            switch v.quality {
            case .premium: qualityScore = 300
            case .enhanced: qualityScore = 200
            default: qualityScore = 100
            }
            let langScore: Int
            if v.language == "en-US" { langScore = 30 }
            else if v.language == "en-GB" { langScore = 20 }
            else { langScore = 10 }
            // Samantha 音色在 Enhanced/Default 里普遍更清晰，轻微偏好
            let samanthaBonus = v.identifier.contains("Samantha") ? 5 : 0
            return qualityScore + langScore + samanthaBonus
        }
        return english.max(by: { rank($0) < rank($1) })
    }

    /// 返回当前选中嗓音的描述（名称+语言+质量），供调试/设置页展示
    var selectedVoiceDescription: String {
        guard let v = bestVoice else { return "系统默认" }
        let quality: String
        switch v.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Default"
        }
        return "\(v.name)（\(v.language)，\(quality)）"
    }

    /// 可用英文嗓音列表，按质量降序、en-US 优先
    var availableVoices: [(identifier: String, label: String)] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { l, r in
                let ql = l.quality.rawValue, qr = r.quality.rawValue
                if ql != qr { return ql > qr }
                let usL = l.language == "en-US" ? 1 : 0
                let usR = r.language == "en-US" ? 1 : 0
                if usL != usR { return usL > usR }
                return l.name < r.name
            }
        return voices.map { v in
            let q: String
            switch v.quality {
            case .premium: q = "★"
            case .enhanced: q = "◆"
            default: q = "·"
            }
            return (v.identifier, "\(q) \(v.name)（\(v.language)）")
        }
    }

    /// 按 identifier 切换嗓音；找不到则保持当前
    func setVoice(identifier: String) {
        if let v = AVSpeechSynthesisVoice(identifier: identifier) {
            bestVoice = v
        }
    }

    // MARK: - 公开方法

    func speak(_ text: String, rate: Float, locale: String) {
        guard !locale.isEmpty else { return } // 关闭发音：不朗读
        stop()
        let utterance = AVSpeechUtterance(string: text)
        // 优先按所选口音（美音/英音）选语音，找不到则退回最佳嗓音
        utterance.voice = AVSpeechSynthesisVoice(language: locale) ?? bestVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        // rate 以系统默认语速为基准换算
        utterance.rate = rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        // 学习场景下稍作停顿，更清晰
        utterance.preUtteranceDelay = 0.05
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

import AVFoundation
import LangSaleCore

/// Speaks translated text aloud. Calls `onIdle` once everything queued has finished,
/// so the app can resume listening.
@MainActor
final class SpeechPlayer: NSObject {
    /// Called when the queue empties, including after `stop()`.
    var onIdle: (() -> Void)?

    /// Playback level from 0 to 1. This scales within the device volume, so 1 is as loud as the phone allows.
    var volume: Float = 1.0

    private let synthesizer = AVSpeechSynthesizer()
    private var queued = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: Language) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceCode(for: language))
        utterance.volume = volume
        queued += 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queued = 0
    }

    /// Haitian Creole has no system voice, so it falls back to the device default.
    private static func voiceCode(for language: Language) -> String? {
        switch language {
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        case .english: "en-US"
        case .haitianCreole: nil
        }
    }

    private func finishOne() {
        queued = max(queued - 1, 0)
        if queued == 0 {
            onIdle?()
        }
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishOne() }
    }
}

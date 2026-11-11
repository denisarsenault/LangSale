import AVFoundation
import LangSaleCore
import Observation
import UIKit

/// Owns the on-device pipeline for the UI. Everything here runs on the main actor;
/// heavy work happens inside the actors and the audio thread in LangSaleCore.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case idle, starting, listening
    }

    private(set) var status: Status = .idle
    private(set) var transcripts: [Transcript] = []
    private(set) var peers: [String] = []
    private(set) var lastError: String?

    var pair: LanguagePair = LanguagePair.firstRelease[0]

    var isRunning: Bool { status != .idle }

    private let ring = AudioRingBuffer(capacity: 16_000 * 60)
    private var capture: AudioCapture?
    private var session: SpeechSession?
    private var pipeline: TranslationPipeline?
    private var sessionListener: Task<Void, Never>?
    private var memoryObserver: NSObjectProtocol?
    private var peerListener: Task<Void, Never>?

    // Sharing stays off until a user-facing approval prompt is wired in; the closure denies everything.
    private let share = PeerTranscriptShare(displayName: "LangSale device") { _ in false }

    private let transcriptLimit = 200

    init() {
        peerListener = Task { [weak self, share] in
            for await event in share.events {
                self?.handlePeer(event)
            }
        }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pipeline?.shedMemory()
            }
        }
    }

    func toggle() async {
        if isRunning {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard status == .idle else { return }
        lastError = nil
        status = .starting

        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = "Microphone access is off. Enable it in Settings to translate."
            status = .idle
            return
        }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [])
            try audio.setActive(true)

            let pipeline = TranslationPipeline(
                recognizer: UnconfiguredSpeechRecognizer(),
                translator: UnconfiguredTranslator(),
                memory: SystemMemoryProbe(),
                pair: pair)
            let session = SpeechSession(ring: ring, pipeline: pipeline)
            let capture = AudioCapture(ring: ring)

            try capture.start()
            await session.start()

            self.pipeline = pipeline
            self.session = session
            self.capture = capture
            sessionListener = Task { [weak self] in
                for await event in session.events {
                    self?.handle(event)
                }
            }
            status = .listening
        } catch {
            lastError = "Could not start audio: \(error.localizedDescription)"
            status = .idle
        }
    }

    func stop() async {
        guard status != .idle else { return }
        capture?.stop()
        capture = nil

        // Let the session flush its last segment through the listener before tearing it down.
        await session?.stop()
        session = nil
        sessionListener?.cancel()
        sessionListener = nil
        pipeline = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = .idle
    }

    private func handle(_ event: SpeechSession.Event) {
        switch event {
        case .transcript(let transcript):
            transcripts.insert(transcript, at: 0)
            if transcripts.count > transcriptLimit {
                transcripts.removeLast(transcripts.count - transcriptLimit)
            }
            try? share.share(transcript)
        case .error(let message):
            lastError = message
        }
    }

    private func handlePeer(_ event: PeerTranscriptShare.Event) {
        switch event {
        case .transcript(let transcript):
            transcripts.insert(transcript, at: 0)
        case .peerConnected(let name):
            if !peers.contains(name) { peers.append(name) }
        case .peerDisconnected(let name):
            peers.removeAll { $0 == name }
        }
    }
}

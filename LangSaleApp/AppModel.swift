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
        case idle, starting, loadingModel, listening
    }

    enum ModelState: Equatable {
        case preparing
        case downloading(fraction: Double)
        case ready
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var modelState: ModelState = .preparing
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
    private var downloader: ModelDownloader?
    private var recognizer: WhisperKitRecognizer?

    // Sharing stays off until a user-facing approval prompt is wired in; the closure denies everything.
    private let share = PeerTranscriptShare(displayName: "LangSale device") { _ in false }

    private let transcriptLimit = 200

    /// - Parameter startsServices: Pass false to skip the model download. Used by previews.
    init(startsServices: Bool = true) {
        peerListener = Task { [weak self, share] in
            for await event in share.events {
                self?.handlePeer(event)
            }
        }
        if startsServices {
            Task { [weak self] in
                await self?.prepareModel()
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
        guard let recognizer, modelState == .ready else {
            lastError = "The speech model is not ready yet."
            return
        }
        lastError = nil
        status = .starting

        guard await AVAudioApplication.requestRecordPermission() else {
            lastError = "Microphone access is off. Enable it in Settings to translate."
            status = .idle
            return
        }

        // Whisper's translate task returns English, so no separate translation model is needed.
        let pipeline = TranslationPipeline(
            recognizer: recognizer,
            translator: nil,
            memory: SystemMemoryProbe(),
            pair: pair)

        // Load before capturing, so the first utterance is not held behind a multi-second
        // load and the UI can show what is happening instead of a silent "listening" state.
        status = .loadingModel
        do {
            try await pipeline.prepare()
        } catch {
            lastError = "Could not load the speech model: \(error)"
            status = .idle
            return
        }
        // The user may have tapped Stop while the model was loading.
        guard status == .loadingModel else { return }

        do {
            try await Self.activateAudioSession()

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

        await Self.deactivateAudioSession()
        status = .idle
    }

    // MARK: - Speech model

    /// Downloads the pinned model files in the background, then prepares the recognizer.
    /// Failed or interrupted files are retried every 30 seconds until the model is complete.
    private func prepareModel() async {
        do {
            let manifest = try SpeechModelStore.currentManifest()
            let modelsRoot = SpeechModelStore.rootDirectory
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(manifest.version, isDirectory: true)
            let downloader = ModelDownloader(manifest: manifest,
                                             store: SpeechModelStore.manifestStore,
                                             modelsDirectory: modelsRoot)
            self.downloader = downloader
            await downloader.start()

            if await downloader.manifest.isComplete {
                markReady(manifest)
                return
            }

            let retry = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    await downloader.resumeIncomplete()
                }
            }
            defer { retry.cancel() }

            for await update in downloader.updates {
                if update.isComplete {
                    markReady(update)
                    return
                }
                let done = update.entries.filter { $0.status == .completed }.count
                modelState = .downloading(fraction: Double(done) / Double(update.entries.count))
            }
        } catch {
            modelState = .failed("Could not prepare the speech model: \(error.localizedDescription)")
        }
    }

    private func markReady(_ manifest: ModelManifest) {
        recognizer = WhisperKitRecognizer(modelFolder: SpeechModelStore.modelFolder(for: manifest))
        modelState = .ready
    }

    // MARK: - Audio session

    /// Configures and activates the shared audio session. `setActive` blocks on a system
    /// call, so it runs on a detached task to keep the main actor responsive.
    private nonisolated static func activateAudioSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [])
            try audio.setActive(true)
        }.value
    }

    /// Deactivates the shared audio session off the main actor. Failures are ignored
    /// because the session is being torn down anyway.
    private nonisolated static func deactivateAudioSession() async {
        await Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
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

#if DEBUG
extension AppModel {
    /// A model with fixed state for SwiftUI previews. Starts no downloads, audio, or networking.
    static func preview(status: Status = .idle,
                        modelState: ModelState = .ready,
                        transcripts: [Transcript] = [],
                        peers: [String] = [],
                        lastError: String? = nil) -> AppModel {
        let model = AppModel(startsServices: false)
        model.status = status
        model.modelState = modelState
        model.transcripts = transcripts
        model.peers = peers
        model.lastError = lastError
        return model
    }

    static let sampleTranscripts: [Transcript] = [
        Transcript(date: Date(timeIntervalSinceNow: -20), source: .spanish, target: .english,
                   original: "¿Tienen esto en una talla más grande?",
                   translated: "Do you have this in a larger size?"),
        Transcript(date: Date(timeIntervalSinceNow: -75), source: .spanish, target: .english,
                   original: "¿Cuánto cuesta con el descuento?",
                   translated: "How much does it cost with the discount?"),
        Transcript(date: Date(timeIntervalSinceNow: -140), source: .spanish, target: .english,
                   original: "Gracias, voy a pensarlo.",
                   translated: "Thank you, I will think about it."),
    ]
}
#endif

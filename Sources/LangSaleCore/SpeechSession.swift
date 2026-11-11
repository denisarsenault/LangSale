import Foundation

/// Drains the audio ring buffer, segments speech with VAD, and feeds each segment to the pipeline.
///
/// Results are delivered on `events`. Segments are capped at 30 s (the recognizer's window)
/// and dropped below 0.5 s to avoid wasting inference on noise.
public actor SpeechSession {
    public enum Event: Sendable, Equatable {
        case transcript(Transcript)
        case error(String)
    }

    public nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let ring: AudioRingBuffer
    private let pipeline: TranslationPipeline
    private var vad: EnergyVAD
    private var segment: [Float] = []
    /// The most recent unvoiced chunks, prepended to a segment when speech starts so the
    /// detector's onset latency does not clip the first syllable.
    private var preroll: [[Float]] = []
    private var worker: Task<Void, Never>?

    private let chunkSize = 512
    private let prerollChunks = 8
    private let maxSegmentSamples = 16_000 * 30
    private let minSegmentSamples = 8_000

    public init(ring: AudioRingBuffer, pipeline: TranslationPipeline,
                vad: EnergyVAD = EnergyVAD()) {
        self.ring = ring
        self.pipeline = pipeline
        self.vad = vad
        let stream = AsyncStream.makeStream(of: Event.self)
        events = stream.stream
        continuation = stream.continuation
    }

    public func start() {
        guard worker == nil else { return }
        worker = Task { await self.run() }
    }

    public func stop() async {
        worker?.cancel()
        await worker?.value
        worker = nil
        await flush()
        continuation.finish()
    }

    private func run() async {
        var scratch = [Float](repeating: 0, count: chunkSize)
        while !Task.isCancelled {
            let n = scratch.withUnsafeMutableBufferPointer { ring.read(into: $0) }
            guard n > 0 else {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            let chunk = Array(scratch[0..<n])
            let event = vad.process(chunk)
            if vad.isSpeaking {
                if event == .speechStarted {
                    segment.append(contentsOf: preroll.joined())
                    preroll.removeAll(keepingCapacity: true)
                }
                segment.append(contentsOf: chunk)
            } else {
                preroll.append(chunk)
                if preroll.count > prerollChunks {
                    preroll.removeFirst()
                }
            }
            if event == .speechEnded || segment.count >= maxSegmentSamples {
                await flush()
            }
        }
    }

    private func flush() async {
        let pcm = segment
        segment.removeAll(keepingCapacity: true)
        guard pcm.count >= minSegmentSamples else { return }
        do {
            if let transcript = try await pipeline.process(segment: pcm) {
                continuation.yield(.transcript(transcript))
            }
        } catch {
            continuation.yield(.error(String(describing: error)))
        }
    }
}

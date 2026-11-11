/// Energy-based voice activity detection over fixed-size chunks of 16 kHz mono PCM.
///
/// Runs on the consumer side, never on the audio thread. The voiced threshold adapts to the
/// background noise level: steady noise (fans, traffic, a busy shop) does not read as speech,
/// and a quiet microphone still triggers on speech that stands out from the room.
///
/// The first `calibrationChunks` after creation only measure the room and never report speech,
/// so start the detector before the user is expected to talk.
public struct EnergyVAD: Sendable {
    public enum Event: Sendable, Equatable {
        case speechStarted
        case speechEnded
    }

    public struct Configuration: Sendable, Equatable {
        /// RMS level a chunk must reach to count as voiced, regardless of how quiet the room is.
        /// Keeps digital silence and very quiet rooms from triggering on their own.
        public var minimumThreshold: Float = 0.006
        /// A chunk is voiced when its RMS exceeds the tracked noise floor by this factor.
        public var noiseRatio: Float = 2.5
        /// Noise floor assumed before any audio has been seen.
        public var initialNoiseFloor: Float = 0.01
        /// Chunks at startup used only to measure the room (about 320 ms at 512 samples).
        public var calibrationChunks = 10
        /// How quickly the noise floor follows quieter chunks (0–1, per chunk).
        public var noiseFallRate: Float = 0.2
        /// How quickly the noise floor follows louder chunks that are not voiced (0–1, per chunk).
        public var noiseRiseRate: Float = 0.02
        /// How quickly the noise floor creeps up during voiced chunks (0–1, per chunk). Kept tiny so
        /// speech is not absorbed, but non-zero so noise that starts mid-session is eventually learned.
        public var voicedRiseRate: Float = 0.001
        /// Consecutive voiced chunks required before speech starts (suppresses clicks).
        public var minVoicedChunks = 3
        /// Silent chunks tolerated before speech ends (keeps short pauses inside one segment).
        public var hangoverChunks = 12

        public init() {}
    }

    public private(set) var isSpeaking = false
    /// Current background noise estimate (RMS). Exposed for calibration and diagnostics.
    public private(set) var noiseFloor: Float
    private let configuration: Configuration
    private var chunksSeen = 0
    private var voicedRun = 0
    private var hangover = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        noiseFloor = configuration.initialNoiseFloor
    }

    /// The RMS level a chunk currently needs to count as voiced.
    public var voicedThreshold: Float {
        max(configuration.minimumThreshold, noiseFloor * configuration.noiseRatio)
    }

    public mutating func process(_ chunk: [Float]) -> Event? {
        guard !chunk.isEmpty else { return nil }
        let meanSquare = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let rms = meanSquare.squareRoot()

        // Startup: converge on the room level quickly and report nothing.
        if chunksSeen < configuration.calibrationChunks {
            chunksSeen += 1
            noiseFloor += (rms - noiseFloor) * configuration.noiseFallRate
            return nil
        }

        if rms >= voicedThreshold {
            noiseFloor += (rms - noiseFloor) * configuration.voicedRiseRate
            voicedRun += 1
            hangover = configuration.hangoverChunks
            if !isSpeaking && voicedRun >= configuration.minVoicedChunks {
                isSpeaking = true
                return .speechStarted
            }
            return nil
        }

        // Unvoiced chunk: let the noise floor track it. Falling is fast so the detector recovers
        // right after loud passages; rising is slower so brief lulls do not lift the threshold.
        let rate = rms < noiseFloor ? configuration.noiseFallRate : configuration.noiseRiseRate
        noiseFloor += (rms - noiseFloor) * rate

        voicedRun = 0
        guard isSpeaking else { return nil }
        hangover -= 1
        if hangover <= 0 {
            isSpeaking = false
            return .speechEnded
        }
        return nil
    }
}

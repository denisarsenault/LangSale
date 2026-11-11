/// Energy-based voice activity detection over fixed-size chunks of 16 kHz mono PCM.
///
/// Runs on the consumer side, never on the audio thread. The threshold is a starting point;
/// calibrate it on device with real microphones and background noise before release.
public struct EnergyVAD: Sendable {
    public enum Event: Sendable, Equatable {
        case speechStarted
        case speechEnded
    }

    public struct Configuration: Sendable, Equatable {
        /// RMS level above which a chunk counts as voiced.
        public var energyThreshold: Float = 0.015
        /// Consecutive voiced chunks required before speech starts (suppresses clicks).
        public var minVoicedChunks = 3
        /// Silent chunks tolerated before speech ends (keeps short pauses inside one segment).
        public var hangoverChunks = 12

        public init() {}
    }

    public private(set) var isSpeaking = false
    private let configuration: Configuration
    private var voicedRun = 0
    private var hangover = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func process(_ chunk: [Float]) -> Event? {
        guard !chunk.isEmpty else { return nil }
        let meanSquare = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let rms = meanSquare.squareRoot()

        if rms >= configuration.energyThreshold {
            voicedRun += 1
            hangover = configuration.hangoverChunks
            if !isSpeaking && voicedRun >= configuration.minVoicedChunks {
                isSpeaking = true
                return .speechStarted
            }
            return nil
        }

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

import AVFoundation

public enum AudioError: Error, Sendable {
    case setupFailed
}

/// Captures the default input, converts it to 16 kHz mono Float32, and writes it into a ring buffer.
///
/// Only `TapProcessor.process` runs on the audio thread. It reuses one preallocated output buffer
/// and performs no allocation of its own beyond what AVAudioConverter does internally.
public final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let ring: AudioRingBuffer
    private var processor: TapProcessor?

    public init(ring: AudioRingBuffer) {
        self.ring = ring
    }

    public func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let processor = try TapProcessor(inputFormat: inputFormat, ring: ring)
        self.processor = processor
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            processor.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        processor = nil
    }

    /// Stops delivering audio while the app plays speech, so the microphone does not hear the app's own voice.
    public func pause() {
        engine.pause()
    }

    public func resume() throws {
        try engine.start()
    }
}

final class TapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputBuffer: AVAudioPCMBuffer
    private let ring: AudioRingBuffer

    init(inputFormat: AVAudioFormat, ring: AudioRingBuffer) throws {
        guard
            let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                       channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: target),
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096)
        else {
            throw AudioError.setupFailed
        }
        self.converter = converter
        self.outputBuffer = outputBuffer
        self.ring = ring
    }

    /// Runs on the audio render thread.
    func process(_ input: AVAudioPCMBuffer) {
        outputBuffer.frameLength = 0
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = outputBuffer.floatChannelData else { return }
        ring.write(UnsafeBufferPointer(start: channel[0], count: Int(outputBuffer.frameLength)))
    }
}

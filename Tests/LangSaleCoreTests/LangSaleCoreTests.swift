import Foundation
import Testing
@testable import LangSaleCore

// MARK: - Ring buffer

@Suite("AudioRingBuffer")
struct AudioRingBufferTests {
    @Test func writeThenReadRoundTrips() {
        let ring = AudioRingBuffer(capacity: 16)
        let input: [Float] = [1, 2, 3, 4]
        let written = input.withUnsafeBufferPointer { ring.write($0) }
        #expect(written == 4)

        var out = [Float](repeating: 0, count: 8)
        let read = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        #expect(read == 4)
        #expect(Array(out[0..<4]) == input)
    }

    @Test func overflowDropsSamplesAndCountsIt() {
        let ring = AudioRingBuffer(capacity: 8)
        let input = [Float](repeating: 1, count: 10)
        let written = input.withUnsafeBufferPointer { ring.write($0) }
        #expect(written == 8)
        #expect(ring.overflowCount == 1)
    }

    @Test func wrapsAroundCapacity() {
        let ring = AudioRingBuffer(capacity: 4)
        var scratch = [Float](repeating: 0, count: 4)
        for round in 0..<5 {
            let input: [Float] = [Float(round), Float(round) + 0.5, Float(round) + 1, Float(round) + 1.5]
            _ = input.withUnsafeBufferPointer { ring.write($0) }
            let n = scratch.withUnsafeMutableBufferPointer { ring.read(into: $0) }
            #expect(n == 4)
            #expect(scratch == input)
        }
    }
}

// MARK: - VAD

@Suite("EnergyVAD")
struct EnergyVADTests {
    private let silence = [Float](repeating: 0, count: 512)
    private let loud = [Float](repeating: 0.5, count: 512)

    @Test func silenceProducesNoEvents() {
        var vad = EnergyVAD()
        for _ in 0..<50 {
            #expect(vad.process(silence) == nil)
        }
        #expect(vad.isSpeaking == false)
    }

    @Test func speechStartsAfterMinimumVoicedChunks() {
        var vad = EnergyVAD()
        #expect(vad.process(loud) == nil)
        #expect(vad.process(loud) == nil)
        #expect(vad.process(loud) == .speechStarted)
        #expect(vad.isSpeaking)
    }

    @Test func speechEndsOnlyAfterHangover() {
        var vad = EnergyVAD(configuration: {
            var c = EnergyVAD.Configuration()
            c.minVoicedChunks = 1
            c.hangoverChunks = 3
            return c
        }())
        _ = vad.process(loud)
        #expect(vad.process(silence) == nil)
        #expect(vad.process(silence) == nil)
        #expect(vad.process(silence) == .speechEnded)
        #expect(vad.isSpeaking == false)
    }
}

// MARK: - Manifest persistence

@Suite("ModelManifest")
struct ModelManifestTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manifest.json")
    }

    @Test func roundTripsIncludingResumeData() throws {
        let store = ManifestStore(url: tempURL())
        let manifest = ModelManifest(version: "1.0.0", entries: [
            .init(fileName: "encoder.mlmodelc.zip",
                  remoteURL: URL(string: "https://example.com/encoder.zip")!,
                  expectedBytes: 1_000,
                  status: .paused,
                  resumeData: Data([0x01, 0x02])),
        ])
        try store.save(manifest)
        let loaded = try store.load()
        #expect(loaded == manifest)
    }

    @Test func missingFileLoadsAsNil() throws {
        let store = ManifestStore(url: tempURL())
        #expect(try store.load() == nil)
    }

    @Test func completeOnlyWhenEveryEntryCompletes() {
        let url = URL(string: "https://example.com/a")!
        var manifest = ModelManifest(version: "1", entries: [
            .init(fileName: "a", remoteURL: url, expectedBytes: 1),
            .init(fileName: "b", remoteURL: url, expectedBytes: 1),
        ])
        #expect(manifest.isComplete == false)
        manifest.entries[0].status = .completed
        #expect(manifest.isComplete == false)
        manifest.entries[1].status = .completed
        #expect(manifest.isComplete)
    }
}

// MARK: - Pipeline

actor FakeRecognizer: SpeechRecognizing {
    nonisolated let name = "fake-asr"
    nonisolated let estimatedFootprintBytes: Int
    private(set) var isLoaded = false
    private let text: String

    init(text: String, footprint: Int) {
        self.text = text
        self.estimatedFootprintBytes = footprint
    }

    func load() async throws { isLoaded = true }
    func unload() async { isLoaded = false }
    func transcribe(_ pcm: [Float], language: Language) async throws -> String { text }
}

actor FakeTranslator: Translating {
    nonisolated let name = "fake-mt"
    nonisolated let estimatedFootprintBytes = 100
    private(set) var isLoaded = false

    func load() async throws { isLoaded = true }
    func unload() async { isLoaded = false }
    func translate(_ text: String, pair: LanguagePair) async throws -> String {
        "EN: \(text)"
    }
}

struct FixedMemory: MemoryProbe {
    let bytes: Int
    func availableBytes() -> Int { bytes }
}

@Suite("TranslationPipeline")
struct TranslationPipelineTests {
    private let pair = LanguagePair(source: .spanish, target: .english)

    @Test func translatesSegmentWhenMemoryAllows() async throws {
        let pipeline = TranslationPipeline(
            recognizer: FakeRecognizer(text: " hola ", footprint: 100),
            translator: FakeTranslator(),
            memory: FixedMemory(bytes: Int.max),
            pair: pair)
        let result = try await pipeline.process(segment: [0.1])
        #expect(result?.original == "hola")
        #expect(result?.translated == "EN: hola")
        #expect(result?.source == .spanish)
    }

    @Test func emptyRecognitionYieldsNoTranscript() async throws {
        let pipeline = TranslationPipeline(
            recognizer: FakeRecognizer(text: "   ", footprint: 100),
            translator: FakeTranslator(),
            memory: FixedMemory(bytes: Int.max),
            pair: pair)
        #expect(try await pipeline.process(segment: [0.1]) == nil)
    }

    @Test func refusesToLoadWithoutHeadroom() async {
        let pipeline = TranslationPipeline(
            recognizer: FakeRecognizer(text: "hola", footprint: 100),
            translator: FakeTranslator(),
            memory: FixedMemory(bytes: 1_000),
            pair: pair)
        await #expect(throws: ModelError.self) {
            _ = try await pipeline.process(segment: [0.1])
        }
    }
}

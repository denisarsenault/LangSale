import Foundation

public struct Transcript: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let source: Language
    public let target: Language
    public let original: String
    public let translated: String

    public init(id: UUID = UUID(), date: Date = Date(), source: Language, target: Language,
                original: String, translated: String) {
        self.id = id
        self.date = date
        self.source = source
        self.target = target
        self.original = original
        self.translated = translated
    }
}

/// Turns one speech segment into a translated transcript.
///
/// Models load lazily and are checked against the memory probe before each load.
/// Calls are serialized by the actor; `SpeechSession` processes one segment at a time.
public actor TranslationPipeline {
    /// Memory that must remain free after a model loads, so the app is not jetsam-killed.
    public static let headroomBytes = 256 * 1024 * 1024

    private let recognizer: any SpeechRecognizing
    /// Nil when the recognizer already returns English (e.g. Whisper's translate task),
    /// in which case the recognized text is used as the translation.
    private let translator: (any Translating)?
    private let memory: any MemoryProbe
    public let pair: LanguagePair
    private var loaded: Set<String> = []

    public init(recognizer: any SpeechRecognizing, translator: (any Translating)?,
                memory: any MemoryProbe, pair: LanguagePair) {
        self.recognizer = recognizer
        self.translator = translator
        self.memory = memory
        self.pair = pair
    }

    /// Loads every model this pipeline needs, checking the memory budget first.
    ///
    /// Call before audio capture starts so the first utterance is not held behind a
    /// multi-second model load. `process` still loads lazily if this was skipped or
    /// if `shedMemory` unloaded the models.
    public func prepare() async throws {
        try await ensureLoaded(recognizer)
        if let translator {
            try await ensureLoaded(translator)
        }
    }

    /// Returns nil when the segment contains no recognizable speech.
    public func process(segment pcm: [Float]) async throws -> Transcript? {
        try await ensureLoaded(recognizer)
        let raw = try await recognizer.transcribe(pcm, language: pair.source)
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }

        guard let translator else {
            return Transcript(source: pair.source, target: pair.target,
                              original: original, translated: original)
        }
        try await ensureLoaded(translator)
        let translated = try await translator.translate(original, pair: pair)
        return Transcript(source: pair.source, target: pair.target,
                          original: original, translated: translated)
    }

    /// Call on memory warnings. Unloads everything; the next segment reloads what it needs.
    public func shedMemory() async {
        await recognizer.unload()
        await translator?.unload()
        loaded.removeAll()
    }

    private func ensureLoaded(_ model: any ManagedModel) async throws {
        guard !loaded.contains(model.name) else { return }
        let needed = model.estimatedFootprintBytes + Self.headroomBytes
        let available = memory.availableBytes()
        guard available >= needed else {
            throw ModelError.insufficientMemory(model: model.name, neededBytes: needed,
                                                availableBytes: available)
        }
        try await model.load()
        loaded.insert(model.name)
    }
}

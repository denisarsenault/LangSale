import LangSaleCore

// Placeholder adapters until vendor models are selected. They refuse to load, so the app
// reports the missing model instead of producing invented translations.

actor UnconfiguredSpeechRecognizer: SpeechRecognizing {
    nonisolated let name = "speech-recognizer"
    nonisolated let estimatedFootprintBytes = 0

    func load() async throws {
        throw ModelError.loadFailed(model: name, reason: "No speech model is installed yet")
    }

    func unload() async {}

    func transcribe(_ pcm: [Float], language: Language) async throws -> String {
        throw ModelError.inferenceFailed(model: name, reason: "Speech model not loaded")
    }
}

actor UnconfiguredTranslator: Translating {
    nonisolated let name = "translator"
    nonisolated let estimatedFootprintBytes = 0

    func load() async throws {
        throw ModelError.loadFailed(model: name, reason: "No translation model is installed yet")
    }

    func unload() async {}

    func translate(_ text: String, pair: LanguagePair) async throws -> String {
        throw ModelError.inferenceFailed(model: name, reason: "Translation model not loaded")
    }
}

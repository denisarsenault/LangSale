//
//  WhisperKitRecognizere.swift
//  LangSale
//
//
//  Created by Denis Arsenault on 11/11/26.
//
//

import Foundation
import LangSaleCore
import WhisperKit

/// Speech recognizer backed by WhisperKit's `whisper-base` Core ML model.
///
/// For directions into English, Whisper's translate task produces English directly from Spanish,
/// Portuguese, or Haitian Creole speech. For English-source directions, it transcribes the English,
/// and `AppleTranslator` translates the text.
///
/// Loads from a local folder only (`download: false`). The model files are placed there by
/// `ModelDownloader`, so the app never fetches from Hugging Face at runtime.
actor WhisperKitRecognizer: SpeechRecognizing {
    nonisolated let name = "whisperkit-base"
    /// Approximate resident size of whisper-base (about 149 MB of weights on disk plus runtime buffers).
    nonisolated let estimatedFootprintBytes = 300 * 1024 * 1024

    private let modelFolder: URL
    private var whisper: WhisperKit?

    /// - Parameter modelFolder: Directory containing `AudioEncoder.mlmodelc`, `MelSpectrogram.mlmodelc`,
    ///   `TextDecoder.mlmodelc`, `config.json`, `generation_config.json`, and `tokenizer.json`.
    init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    func load() async throws {
        // Already resident: keep it. Each Stop/Start cycle builds a new pipeline, and
        // rebuilding WhisperKit costs several seconds of silence.
        guard whisper == nil else { return }
        do {
            let config = WhisperKitConfig(modelFolder: modelFolder.path,
                                          verbose: false,
                                          load: true,
                                          download: false)
            whisper = try await WhisperKit(config)
        } catch {
            throw ModelError.loadFailed(model: name, reason: error.localizedDescription)
        }
    }

    func unload() async {
        whisper = nil
    }

    func transcribe(_ pcm: [Float], pair: LanguagePair) async throws -> String {
        guard let whisper else {
            throw ModelError.inferenceFailed(model: name, reason: "Model is not loaded")
        }
        // Translate to English when English is the target (Spanish, Portuguese, Creole → English).
        // Otherwise transcribe in the source language; a translation model handles the rest.
        let task: DecodingTask = pair.target == .english ? .translate : .transcribe
        let options = DecodingOptions(task: task, language: pair.source.rawValue)
        let results = await whisper.transcribe(audioArrays: [pcm], decodeOptions: options)
        guard let segments = results.first ?? nil else {
            throw ModelError.inferenceFailed(model: name, reason: "Transcription returned no result")
        }
        return segments.map(\.text).joined(separator: " ")
    }
}

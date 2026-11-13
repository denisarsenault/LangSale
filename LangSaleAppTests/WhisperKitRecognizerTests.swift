import Foundation
import LangSaleCore
import Testing
@testable import LangSale

@Suite("WhisperKitRecognizer")
struct WhisperKitRecognizerTests {
    private let missingFolder = URL(fileURLWithPath: "/nonexistent-langsale-model")

    @Test func transcribeBeforeLoadThrows() async {
        let recognizer = WhisperKitRecognizer(modelFolder: missingFolder)
        await #expect(throws: ModelError.self) {
            _ = try await recognizer.transcribe([0.0, 0.1],
                                                pair: LanguagePair(source: .spanish, target: .english))
        }
    }

    @Test func loadFromMissingFolderThrowsLoadError() async {
        let recognizer = WhisperKitRecognizer(modelFolder: missingFolder)
        await #expect(throws: ModelError.self) {
            try await recognizer.load()
        }
    }

    @Test func unloadWithNothingLoadedIsSafe() async {
        let recognizer = WhisperKitRecognizer(modelFolder: missingFolder)
        await recognizer.unload()
        await recognizer.unload()
    }

    @Test func declaresAFootprintForBudgeting() {
        let recognizer = WhisperKitRecognizer(modelFolder: missingFolder)
        #expect(recognizer.estimatedFootprintBytes > 0)
        #expect(recognizer.name == "whisperkit-base")
    }
}

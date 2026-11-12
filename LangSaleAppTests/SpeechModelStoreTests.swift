import Foundation
import LangSaleCore
import Testing
@testable import LangSale

@Suite("SpeechModelStore")
struct SpeechModelStoreTests {
    @Test func modelFolderNestsUnderVersionAndWhisperFolder() {
        let manifest = ModelManifest(version: "whisper-base-test", entries: [])
        let folder = SpeechModelStore.modelFolder(for: manifest)
        #expect(folder.lastPathComponent == "openai_whisper-base")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "whisper-base-test")
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Models")
    }

    @Test func bundledManifestPinsWhisperBaseFiles() throws {
        let manifest = try SpeechModelStore.bundledManifest()
        #expect(manifest.version.hasPrefix("whisper-base-"))
        #expect(!manifest.entries.isEmpty)
        #expect(manifest.entries.contains { $0.fileName == "openai_whisper-base/tokenizer.json" })
        #expect(manifest.entries.contains { $0.fileName == "openai_whisper-base/AudioEncoder.mlmodelc/weights/weight.bin" })
        #expect(manifest.entries.allSatisfy { $0.status == .pending })
    }

    @Test func bundledManifestUsesPinnedCommitURLs() throws {
        let manifest = try SpeechModelStore.bundledManifest()
        // Every file must come from a fixed commit (a 40-character hash), never a moving branch.
        for entry in manifest.entries {
            let parts = entry.remoteURL.pathComponents
            let resolveIndex = try #require(parts.firstIndex(of: "resolve"))
            let commit = parts[resolveIndex + 1]
            #expect(commit.count == 40, "\(entry.fileName) is not pinned to a full commit")
            #expect(commit != "main")
        }
    }
}

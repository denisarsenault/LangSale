import Foundation
import LangSaleCore

/// Locates the speech model on disk and drives its background download.
///
/// The bundled manifest is the release definition, with pinned Hugging Face commits. The
/// persisted copy in Application Support keeps download progress across launches. If the release
/// version changes, the persisted copy is replaced.
enum SpeechModelStore {
    static let bundledManifestName = "whisper-base.manifest.json"

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LangSale", isDirectory: true)
    }

    static var manifestStore: ManifestStore {
        ManifestStore(url: rootDirectory.appendingPathComponent("speech-model-manifest.json"))
    }

    /// The directory WhisperKit loads from. Matches the manifest's top-level folder, `openai_whisper-base`.
    static func modelFolder(for manifest: ModelManifest) -> URL {
        rootDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(manifest.version, isDirectory: true)
            .appendingPathComponent("openai_whisper-base", isDirectory: true)
    }

    static func bundledManifest() throws -> ModelManifest {
        guard let url = Bundle.main.url(forResource: "whisper-base.manifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }

    /// Returns the persisted manifest if it matches the bundled release, otherwise the bundled one.
    static func currentManifest() throws -> ModelManifest {
        let bundled = try bundledManifest()
        if let persisted = try manifestStore.load(), persisted.version == bundled.version {
            return persisted
        }
        return bundled
    }
}

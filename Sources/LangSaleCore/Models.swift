#if os(iOS)
import os
#endif

/// A vendor-supplied model with an explicit lifecycle and a declared memory footprint.
/// Concrete adapters (Core ML, ONNX Runtime, WhisperKit) live in the app target and conform to these.
public protocol ManagedModel: Sendable {
    var name: String { get }
    /// Resident memory the model needs once loaded, in bytes. Used for budgeting before load.
    var estimatedFootprintBytes: Int { get }
    func load() async throws
    func unload() async
}

public protocol SpeechRecognizing: ManagedModel {
    /// `pcm` is 16 kHz mono Float32.
    func transcribe(_ pcm: [Float], language: Language) async throws -> String
}

public protocol Translating: ManagedModel {
    func translate(_ text: String, pair: LanguagePair) async throws -> String
}

public enum ModelError: Error, Equatable, Sendable {
    case insufficientMemory(model: String, neededBytes: Int, availableBytes: Int)
    case loadFailed(model: String, reason: String)
    case inferenceFailed(model: String, reason: String)
}

/// Reports how much memory this process may still allocate before jetsam.
public protocol MemoryProbe: Sendable {
    func availableBytes() -> Int
}

public struct SystemMemoryProbe: MemoryProbe {
    public init() {}

    public func availableBytes() -> Int {
        #if os(iOS)
        return Int(os_proc_available_memory())
        #else
        return Int.max
        #endif
    }
}

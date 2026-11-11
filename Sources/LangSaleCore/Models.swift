import Foundation
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
        // `os_proc_available_memory` returns 0 when the process has no jetsam limit
        // (notably in the Simulator) or when the query fails. Zero would wrongly block
        // every model load, so fall back to an estimate in that case.
        let reported = Int(os_proc_available_memory())
        if reported > 0 {
            return reported
        }
        #endif
        return Self.estimatedAvailableBytes()
    }

    /// Physical memory minus this process's current footprint. Used when the system
    /// does not report a per-process limit.
    private static func estimatedAvailableBytes() -> Int {
        let physical = Int(clamping: ProcessInfo.processInfo.physicalMemory)
        return max(physical - residentFootprintBytes(), 0)
    }

    /// The process's physical footprint as reported by Mach, or 0 if the query fails.
    private static func residentFootprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(clamping: info.phys_footprint)
    }
}

import Synchronization

/// Single-producer, single-consumer ring buffer of Float samples.
///
/// The producer (audio render thread) calls `write`, which never allocates and never locks.
/// The consumer (a background task) calls `read`. Indices are monotonic; wrap-around is a modulo.
/// When the consumer falls behind, new samples are dropped and counted rather than blocking the audio thread.
public final class AudioRingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    public let capacity: Int
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let overflows = Atomic<Int>(0)

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Number of write calls that dropped samples because the buffer was full.
    public var overflowCount: Int { overflows.load(ordering: .relaxed) }

    /// Producer side. Real-time safe. Returns the number of samples accepted.
    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        let free = capacity - (w - r)
        let n = min(free, samples.count)
        for i in 0..<n {
            storage[(w + i) % capacity] = samples[i]
        }
        writeIndex.store(w + n, ordering: .releasing)
        if n < samples.count {
            _ = overflows.add(1, ordering: .relaxed)
        }
        return n
    }

    /// Consumer side. Copies up to `dst.count` samples and returns how many were copied.
    public func read(into dst: UnsafeMutableBufferPointer<Float>) -> Int {
        let r = readIndex.load(ordering: .relaxed)
        let w = writeIndex.load(ordering: .acquiring)
        let n = min(w - r, dst.count)
        for i in 0..<n {
            dst[i] = storage[(r + i) % capacity]
        }
        readIndex.store(r + n, ordering: .releasing)
        return n
    }
}

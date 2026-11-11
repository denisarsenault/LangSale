import Foundation
import Network

/// The persisted record of one model release: which files are needed and how far each has got.
public struct ModelManifest: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending, downloading, paused, failed, completed
    }

    public struct Entry: Codable, Sendable, Equatable {
        public let fileName: String
        public let remoteURL: URL
        public let expectedBytes: Int64
        public var status: Status
        /// Resume data from an interrupted transfer. Cleared once the file completes.
        public var resumeData: Data?

        public init(fileName: String, remoteURL: URL, expectedBytes: Int64,
                    status: Status = .pending, resumeData: Data? = nil) {
            self.fileName = fileName
            self.remoteURL = remoteURL
            self.expectedBytes = expectedBytes
            self.status = status
            self.resumeData = resumeData
        }
    }

    public let version: String
    public var entries: [Entry]

    public init(version: String, entries: [Entry]) {
        self.version = version
        self.entries = entries
    }

    public var isComplete: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.status == .completed }
    }
}

/// Atomically persists the manifest so downloads survive app termination.
public struct ManifestStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> ModelManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }

    public func save(_ manifest: ModelManifest) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
    }
}

public enum DownloadEvent: Sendable {
    case finished(fileName: String, destination: URL)
    case failed(fileName: String, resumeData: Data?, message: String)
}

/// Bridges URLSession callbacks into an AsyncStream. Moves finished files into place
/// synchronously, because URLSession deletes the temporary file when the callback returns.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationDirectory: URL
    private let emit: @Sendable (DownloadEvent) -> Void

    init(destinationDirectory: URL, emit: @escaping @Sendable (DownloadEvent) -> Void) {
        self.destinationDirectory = destinationDirectory
        self.emit = emit
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let name = downloadTask.taskDescription else { return }
        let destination = destinationDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: destinationDirectory,
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            emit(.finished(fileName: name, destination: destination))
        } catch {
            emit(.failed(fileName: name, resumeData: nil, message: error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A nil error means the file finished; didFinishDownloadingTo already handled it.
        guard let error, let name = task.taskDescription else { return }
        let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        emit(.failed(fileName: name, resumeData: resume, message: error.localizedDescription))
    }
}

/// Downloads every file in a manifest over a background URLSession.
///
/// Interrupted transfers keep their resume data. Network changes trigger a retry of anything incomplete.
/// Call `start()` on every launch: it reattaches to tasks the system kept running.
public actor ModelDownloader {
    public static let sessionIdentifier = "com.langsale.models"

    public private(set) var manifest: ModelManifest
    private let store: ManifestStore
    private let modelsDirectory: URL
    private let session: URLSession
    private let events: AsyncStream<DownloadEvent>
    private let monitor = NWPathMonitor()
    private var online = true
    private var consumer: Task<Void, Never>?

    public init(manifest: ModelManifest, store: ManifestStore, modelsDirectory: URL,
                allowsCellular: Bool = false) {
        self.manifest = manifest
        self.store = store
        self.modelsDirectory = modelsDirectory

        let stream = AsyncStream.makeStream(of: DownloadEvent.self)
        events = stream.stream
        let delegate = DownloadDelegate(destinationDirectory: modelsDirectory) {
            stream.continuation.yield($0)
        }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = allowsCellular
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func start() async {
        consumer = Task { for await event in self.events { self.handle(event) } }

        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { await self?.networkChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "langsale.network"))

        await resumeIncomplete()
    }

    public func localURL(for fileName: String) -> URL {
        modelsDirectory.appendingPathComponent(fileName)
    }

    private func networkChanged(satisfied: Bool) async {
        online = satisfied
        if satisfied { await resumeIncomplete() }
    }

    private func resumeIncomplete() async {
        let active = Set(await session.allTasks.compactMap(\.taskDescription))
        for entry in manifest.entries where entry.status != .completed && !active.contains(entry.fileName) {
            startTask(for: entry)
        }
    }

    private func startTask(for entry: ModelManifest.Entry) {
        let task: URLSessionDownloadTask
        if let data = entry.resumeData {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: entry.remoteURL)
        }
        task.taskDescription = entry.fileName
        mutate(entry.fileName) { $0.status = .downloading }
        task.resume()
    }

    private func handle(_ event: DownloadEvent) {
        switch event {
        case .finished(let name, _):
            mutate(name) {
                $0.status = .completed
                $0.resumeData = nil
            }
        case .failed(let name, let resume, _):
            mutate(name) {
                $0.resumeData = resume ?? $0.resumeData
                $0.status = (resume != nil || !online) ? .paused : .failed
            }
        }
    }

    private func mutate(_ name: String, _ body: (inout ModelManifest.Entry) -> Void) {
        guard let index = manifest.entries.firstIndex(where: { $0.fileName == name }) else { return }
        body(&manifest.entries[index])
        // Persistence failure leaves the in-memory state correct; the next change retries the save.
        try? store.save(manifest)
    }
}

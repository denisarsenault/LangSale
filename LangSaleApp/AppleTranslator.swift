import Foundation
import LangSaleCore
import Translation

/// English → Spanish or Portuguese translation with Apple's on-device Translation framework.
///
/// The framework hands out a `TranslationSession` only inside a SwiftUI `translationTask`. ContentView
/// hosts that task, and `serve(_:)` answers requests from `translate` while the task is active.
/// A request made while no session is active fails straight away instead of waiting.
@MainActor
final class AppleTranslator: Translating {
    nonisolated let name = "apple-translation"
    /// The framework keeps its language models outside this process, so they do not count against the app's budget.
    nonisolated let estimatedFootprintBytes = 0

    private struct Request {
        let text: String
        let reply: CheckedContinuation<String, Error>
    }

    private let requests: AsyncStream<Request>
    private let enqueue: AsyncStream<Request>.Continuation
    private var isServing = false

    init() {
        let stream = AsyncStream.makeStream(of: Request.self)
        requests = stream.stream
        enqueue = stream.continuation
    }

    /// Waits up to 15 seconds for SwiftUI to start the translation task for the current target.
    func load() async throws {
        var waited = 0
        while !isServing && waited < 150 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard isServing else {
            throw ModelError.loadFailed(model: name, reason: "Translation is not available for this language yet")
        }
    }

    func unload() async {
        // The session belongs to SwiftUI, so there is nothing to release here.
    }

    func translate(_ text: String, pair: LanguagePair) async throws -> String {
        guard isServing else {
            throw ModelError.inferenceFailed(model: name, reason: "Translation session is not active")
        }
        return try await withCheckedThrowingContinuation { reply in
            enqueue.yield(Request(text: text, reply: reply))
        }
    }

    /// Answers queued requests until the translation task is cancelled, for example when the target language changes.
    func serve(_ session: TranslationSession) async {
        isServing = true
        defer { isServing = false }
        // TranslationSession is not Sendable, but this loop is the only caller and runs its requests one at a time.
        nonisolated(unsafe) let translationSession = session
        for await request in requests {
            do {
                let response = try await translationSession.translate(request.text)
                request.reply.resume(returning: response.targetText)
            } catch {
                request.reply.resume(throwing: ModelError.inferenceFailed(model: name,
                                                                          reason: error.localizedDescription))
            }
        }
    }
}

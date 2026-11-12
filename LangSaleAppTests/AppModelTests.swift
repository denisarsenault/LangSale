import Foundation
import LangSaleCore
import Testing
@testable import LangSale

@MainActor
@Suite("AppModel")
struct AppModelTests {
    @Test func defaultDirectionIsFirstReleasePair() {
        let model = AppModel.preview()
        #expect(model.pair == LanguagePair.firstRelease[0])
        #expect(model.pair.target == .english)
    }

    @Test func startIsRefusedWhileModelIsDownloading() async {
        let model = AppModel.preview(modelState: .downloading(fraction: 0.5))
        await model.start()
        #expect(model.status == .idle)
        #expect(model.lastError == "The speech model is not ready yet.")
    }

    @Test func startIsRefusedWhenModelFailed() async {
        let model = AppModel.preview(modelState: .failed("offline"))
        await model.start()
        #expect(model.status == .idle)
        #expect(model.isRunning == false)
    }

    @Test func stopWhenIdleChangesNothing() async {
        let model = AppModel.preview()
        await model.stop()
        #expect(model.status == .idle)
        #expect(model.lastError == nil)
    }

    @Test func stopReturnsListeningModelToIdle() async {
        let model = AppModel.preview(status: .listening)
        #expect(model.isRunning)
        await model.stop()
        #expect(model.status == .idle)
        #expect(model.isRunning == false)
    }

    @Test func toggleStopsWhenRunning() async {
        let model = AppModel.preview(status: .listening)
        await model.toggle()
        #expect(model.status == .idle)
    }

    @Test func previewCarriesProvidedTranscriptsAndPeers() {
        let model = AppModel.preview(transcripts: AppModel.sampleTranscripts,
                                     peers: ["Front counter iPad"])
        #expect(model.transcripts.count == AppModel.sampleTranscripts.count)
        #expect(model.peers == ["Front counter iPad"])
    }
}

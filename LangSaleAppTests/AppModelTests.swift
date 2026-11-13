import Foundation
import LangSaleCore
import Testing
@testable import LangSale

@MainActor
@Suite("AppModel")
struct AppModelTests {
    @Test func defaultDirectionIsEnglishToSpanish() {
        let model = AppModel.preview()
        #expect(model.pair == LanguagePair(source: .english, target: .spanish))
        #expect(model.translationConfiguration != nil)
    }

    @Test func englishToEnglishTargetsNeedNoTranslationSession() {
        let model = AppModel.preview()
        model.pair = LanguagePair(source: .spanish, target: .english)
        #expect(model.translationConfiguration == nil)
        model.pair = LanguagePair(source: .english, target: .portuguese)
        #expect(model.translationConfiguration != nil)
    }

    @Test func creoleTargetHasNoTranslationSession() {
        let model = AppModel.preview()
        model.pair = LanguagePair(source: .english, target: .haitianCreole)
        #expect(model.translationConfiguration == nil)
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

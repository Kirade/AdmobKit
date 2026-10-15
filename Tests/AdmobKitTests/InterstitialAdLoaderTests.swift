import XCTest
@testable import AdmobKit

@MainActor
final class InterstitialAdLoaderTests: XCTestCase {
    
    private var source: FakeAdSource!
    private var sleeper: FakeSleeper!
    private var clock: FakeClock!
    
    override func setUp() async throws {
        source = FakeAdSource()
        sleeper = FakeSleeper()
        clock = FakeClock()
    }
    
    private func makeLoader(canRequestAds: Bool = true) -> InterstitialAdLoader {
        let source = source!
        let sleeper = sleeper!
        let clock = clock!
        return InterstitialAdLoader(
            waitUntilAdsCanBeRequested: { canRequestAds },
            loadAd: { try await source.load($0) },
            sleep: { await sleeper.sleep($0) },
            now: { clock.now }
        )
    }
    
    func testShowWithoutLoadedAdCallsOnDismissImmediately() async {
        let loader = makeLoader(canRequestAds: false)
        var dismissed = 0
        
        loader.showAd { dismissed += 1 }
        
        XCTAssertEqual(dismissed, 1)
    }
    
    func testLoadedAdIsPresentedAndCallbackRunsOnClose() async {
        let ad = FakeAd()
        source.results = [.success(ad)]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        var dismissed = 0
        
        loader.showAd { dismissed += 1 }
        XCTAssertEqual(ad.presentCount, 1)
        XCTAssertEqual(dismissed, 0)
        
        ad.dismiss()
        await settle()
        XCTAssertEqual(dismissed, 1)
    }
    
    // MARK: - Retry
    
    func testLoadAdWhileRetryIsPendingKeepsBackoffGoing() async {
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        XCTAssertEqual(source.loadCount, 1)
        XCTAssertEqual(sleeper.retryDelays, [5])
        
        // e.g. `.onAppear { loadAd() }` firing again while the retry waits
        loader.loadAd()
        await settle()
        XCTAssertEqual(source.loadCount, 1)
        
        sleeper.wake(delay: 5)
        await settle()
        XCTAssertEqual(source.loadCount, 2)
        XCTAssertEqual(sleeper.retryDelays, [5, 10])
    }
    
    func testRetriesStopAfterFiveAttemptsUntilNextLoadAd() async {
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        for delay in RetryBackoff.defaultDelays {
            sleeper.wake(delay: delay)
            await settle()
        }
        XCTAssertEqual(source.loadCount, 6)
        XCTAssertEqual(sleeper.retryDelays, [5, 10, 20, 40, 60])
        
        loader.loadAd()
        await settle()
        
        XCTAssertEqual(source.loadCount, 7)
        XCTAssertEqual(sleeper.retryDelays, [5, 10, 20, 40, 60, 5])
    }
    
    func testReleasingLoaderCancelsPendingRetry() async {
        var loader: InterstitialAdLoader? = makeLoader()
        loader?.loadAd()
        await settle()
        XCTAssertEqual(sleeper.retryDelays, [5])
        
        loader = nil
        await settle()
        
        XCTAssertEqual(sleeper.cancelledCount, 1)
    }
    
    // MARK: - Expiry
    
    func testAdExpiredWhileInBackgroundIsNotShown() async {
        let ad = FakeAd()
        source.results = [.success(ad)]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        clock.now = clock.now.addingTimeInterval(2 * 60 * 60)
        var dismissed = 0
        
        loader.showAd { dismissed += 1 }
        await settle()
        
        XCTAssertEqual(ad.presentCount, 0)
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(source.loadCount, 2)
    }
    
    func testUnshownAdIsReplacedAfterFiftyFiveMinutes() async {
        source.results = [.success(FakeAd())]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        XCTAssertEqual(source.loadCount, 1)
        
        sleeper.wake(delay: AdFreshness.lifetime)
        await settle()
        
        XCTAssertEqual(source.loadCount, 2)
    }
    
    // MARK: - Presenting
    
    func testAdThatCannotBePresentedIsSkippedAndReloaded() async {
        let ad = FakeAd()
        ad.presentError = TestError()
        source.results = [.success(ad)]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        var dismissed = 0
        
        loader.showAd { dismissed += 1 }
        await settle()
        
        XCTAssertEqual(ad.presentCount, 0)
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(source.loadCount, 2)
    }
    
    func testShowWhilePresentingRunsBothCallbacksOnClose() async {
        let ad = FakeAd()
        source.results = [.success(ad)]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        var dismissed = 0
        
        loader.showAd { dismissed += 1 }
        loader.showAd { dismissed += 1 }
        XCTAssertEqual(ad.presentCount, 1)
        XCTAssertEqual(dismissed, 0)
        
        ad.dismiss()
        await settle()
        XCTAssertEqual(dismissed, 2)
    }
    
    func testOnDismissCanShowAgainWhileTheAdCloses() async {
        let first = FakeAd()
        let second = FakeAd()
        source.results = [.success(first), .success(second)]
        let loader = makeLoader()
        loader.loadAd()
        await settle()
        var events: [String] = []
        
        loader.showAd {
            events.append("first closed")
            loader.showAd { events.append("second skipped") }
        }
        first.dismiss()
        await settle()
        
        // The next ad was still loading when onDismiss ran, so the nested request ends at once.
        XCTAssertEqual(events, ["first closed", "second skipped"])
        loader.showAd { events.append("second closed") }
        XCTAssertEqual(second.presentCount, 1)
    }
}

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
}

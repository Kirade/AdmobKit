import XCTest
@testable import AdmobKit

@MainActor
final class AdsStartupCoordinatorTests: XCTestCase {
    
    private func makeCoordinator(_ consent: FakeConsentGateway) -> AdsStartupCoordinator {
        AdsStartupCoordinator(
            consent: consent,
            startSDK: { consent.record("sdkStart") },
            waitForWindow: { consent.record("window") }
        )
    }
    
    func testRunsConsentStepsInOrderBeforeStartingSDK() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertTrue(coordinator.isSDKStarted)
        XCTAssertEqual(consent.events, ["update", "window", "form", "sdkStart"])
    }
    
    func testRepeatedAndConcurrentStartsRunOnce() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        async let first = coordinator.start(debugSettings: nil)
        async let second = coordinator.start(debugSettings: nil)
        let results = await [first, second]
        let third = await coordinator.start(debugSettings: nil)
        
        XCTAssertEqual(results, [true, true])
        XCTAssertTrue(third)
        XCTAssertEqual(consent.count("update"), 1)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testDoesNotStartSDKWhenAdsCannotBeRequested() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertFalse(canRequestAds)
        XCTAssertFalse(coordinator.isSDKStarted)
        XCTAssertEqual(consent.count("sdkStart"), 0)
    }
    
    func testSkipsFormAndUsesPreviousConsentWhenUpdateFails() async {
        let consent = FakeConsentGateway()
        consent.updateError = TestError()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.events, ["update", "sdkStart"])
    }
    
    func testUpdateFailureWithoutPreviousConsentRequestsNoAds() async {
        let consent = FakeConsentGateway()
        consent.updateError = TestError()
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertFalse(canRequestAds)
        XCTAssertEqual(consent.events, ["update"])
    }
    
    func testContinuesWhenConsentFormFails() async {
        let consent = FakeConsentGateway()
        consent.formError = TestError()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testConsentGivenInFormStartsSDK() async {
        let consent = FakeConsentGateway()
        consent.canRequestAdsAfterForm = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testPrivacyOptionsEnablingAdsStartsSDKOnce() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        let initiallyAllowed = await coordinator.start(debugSettings: nil)
        consent.canRequestAdsAfterPrivacyOptions = true
        
        let allowedAfterOptions = await coordinator.presentPrivacyOptions()
        let allowedLater = await coordinator.start(debugSettings: nil)
        
        XCTAssertFalse(initiallyAllowed)
        XCTAssertTrue(allowedAfterOptions)
        XCTAssertTrue(allowedLater)
        XCTAssertTrue(coordinator.isSDKStarted)
        XCTAssertEqual(consent.count("sdkStart"), 1)
        XCTAssertEqual(consent.count("update"), 1)
    }
    
    func testPrivacyOptionsFailureKeepsSDKRunning() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        _ = await coordinator.start(debugSettings: nil)
        consent.privacyOptionsError = TestError()
        
        let canRequestAds = await coordinator.presentPrivacyOptions()
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testReflectsPrivacyOptionsRequirement() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        consent.isPrivacyOptionsRequired = true
        let coordinator = makeCoordinator(consent)
        
        _ = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(coordinator.isPrivacyOptionsRequired)
    }
    
    func testResetConsentClearsPrivacyOptionsRequirement() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        consent.isPrivacyOptionsRequired = true
        let coordinator = makeCoordinator(consent)
        _ = await coordinator.start(debugSettings: nil)
        
        coordinator.resetConsent()
        
        XCTAssertEqual(consent.count("reset"), 1)
        XCTAssertFalse(coordinator.isPrivacyOptionsRequired)
    }
    
    func testPrivacyOptionsRefreshesPrivacyOptionsRequirement() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        _ = await coordinator.start(debugSettings: nil)
        consent.isPrivacyOptionsRequired = true
        
        _ = await coordinator.presentPrivacyOptions()
        
        XCTAssertTrue(coordinator.isPrivacyOptionsRequired)
    }
    
    func testPassesDebugSettingsToConsentUpdate() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        let settings = ConsentDebugSettings(geography: .eea, testDeviceIdentifiers: ["TEST-DEVICE"])
        
        _ = await coordinator.start(debugSettings: settings)
        
        XCTAssertEqual(consent.receivedDebugSettings, [settings])
    }
    
    func testWaitingForSDKStartReturnsImmediatelyWhenAdsAreAllowed() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        await coordinator.waitUntilSDKStarted(debugSettings: nil)
        
        XCTAssertTrue(coordinator.isSDKStarted)
    }
    
    func testWaiterResumesWhenPrivacyOptionsLaterAllowAds() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        _ = await coordinator.start(debugSettings: nil)
        
        // A banner already on screen keeps waiting while ads are not allowed.
        let waiter = Task {
            await coordinator.waitUntilSDKStarted(debugSettings: nil)
            consent.record("waiterResumed")
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(consent.count("waiterResumed"), 0)
        
        consent.canRequestAdsAfterPrivacyOptions = true
        _ = await coordinator.presentPrivacyOptions()
        await waiter.value
        
        XCTAssertEqual(consent.count("waiterResumed"), 1)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
}

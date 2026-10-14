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
    
    func testContinuesWithPreviousConsentWhenUpdateFails() async {
        let consent = FakeConsentGateway()
        consent.updateError = TestError()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.events, ["update", "window", "form", "sdkStart"])
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
    
    func testPassesDebugSettingsToConsentUpdate() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        let settings = ConsentDebugSettings(geography: .eea, testDeviceIdentifiers: ["TEST-DEVICE"])
        
        _ = await coordinator.start(debugSettings: settings)
        
        XCTAssertEqual(consent.receivedDebugSettings, [settings])
    }
}

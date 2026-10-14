@testable import AdmobKit

struct TestError: Error {}

/// Records every consent step so tests can check order and counts.
@MainActor
final class FakeConsentGateway: ConsentGateway {

    var canRequestAds = false
    var isPrivacyOptionsRequired = false
    var updateError: Error?
    var formError: Error?
    var privacyOptionsError: Error?
    /// Simulates the user's choice in the consent form.
    var canRequestAdsAfterForm: Bool?
    /// Simulates the user's choice in the privacy options form.
    var canRequestAdsAfterPrivacyOptions: Bool?

    private(set) var events: [String] = []
    private(set) var receivedDebugSettings: [ConsentDebugSettings?] = []

    func record(_ event: String) {
        events.append(event)
    }

    func count(_ event: String) -> Int {
        events.filter { $0 == event }.count
    }

    func requestUpdate(debugSettings: ConsentDebugSettings?) async throws {
        record("update")
        receivedDebugSettings.append(debugSettings)
        if let updateError = updateError { throw updateError }
    }

    func loadAndPresentIfRequired() async throws {
        record("form")
        if let canRequestAdsAfterForm = canRequestAdsAfterForm { canRequestAds = canRequestAdsAfterForm }
        if let formError = formError { throw formError }
    }

    func presentPrivacyOptions() async throws {
        record("privacyOptions")
        if let canRequestAdsAfterPrivacyOptions = canRequestAdsAfterPrivacyOptions {
            canRequestAds = canRequestAdsAfterPrivacyOptions
        }
        if let privacyOptionsError = privacyOptionsError { throw privacyOptionsError }
    }

    func reset() {
        record("reset")
        canRequestAds = false
    }
}

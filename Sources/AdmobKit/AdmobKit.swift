//
//  AdmobKit.swift
//  AdmobKit
//
//  A reusable AdMob integration library for iOS apps.
//

import Combine
import Foundation
import GoogleMobileAds

/// Main entry point for AdmobKit configuration and initialization.
///
/// Usage:
/// ```swift
/// // In your App's init
/// AdmobKit.configure(bannerAdUnitID: "ca-app-pub-xxx/yyy")
/// AdmobKit.shared.initialize()  // Gathers consent where required, then starts the SDK
/// ```
@MainActor
public final class AdmobKit: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance for SDK operations
    public static let shared = AdmobKit()
    
    // MARK: - Configuration Storage
    
    private static var _bannerAdUnitID: String?
    private static var _interstitialAdUnitID: String?
    private static var _rewardedAdUnitID: String?
    private static var consentDebugSettings: ConsentDebugSettings?
    
    // MARK: - Properties
    
    /// Indicates whether the Google Mobile Ads SDK has started and ads can be requested
    @Published public private(set) var isInitialized = false
    
    /// Whether this user must be offered a way to change their privacy choices
    /// (for example, users in the EEA). Show `PrivacyOptionsButton` in your settings screen.
    @Published public private(set) var isPrivacyOptionsRequired = false
    
    private let startup: AdsStartupCoordinator
    
    // MARK: - Init
    
    private init() {
        startup = AdsStartupCoordinator(
            consent: UMPConsentGateway(),
            startSDK: {
                let status = await MobileAds.shared.start()
                #if DEBUG
                AdmobKit.logInitializationStatus(status)
                #endif
            },
            waitForWindow: { await KeyWindow.wait() }
        )
    }
    
    // MARK: - Configuration
    
    /// Configure AdmobKit with your ad unit IDs.
    ///
    /// Call this method once at app launch, before calling `initialize()`.
    /// Test ads are automatically used in Debug and TestFlight builds.
    ///
    /// - Parameters:
    ///   - bannerAdUnitID: Your production banner ad unit ID
    ///   - interstitialAdUnitID: Your production interstitial ad unit ID (optional)
    ///   - rewardedAdUnitID: Your production rewarded ad unit ID (optional)
    public static func configure(
        bannerAdUnitID: String? = nil,
        interstitialAdUnitID: String? = nil,
        rewardedAdUnitID: String? = nil
    ) {
        _bannerAdUnitID = bannerAdUnitID
        _interstitialAdUnitID = interstitialAdUnitID
        _rewardedAdUnitID = rewardedAdUnitID
        
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📦 AdmobKit configured")
        print("   Banner ID: \(bannerAdUnitID ?? "not set")")
        print("   Environment: \(AdConfig.environmentDescription)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
    }
    
    // MARK: - Consent Debugging
    
    /// Simulates a region for the consent flow. Applied in Debug builds only; ignored in Release.
    ///
    /// Call before `initialize()`. Combine with `resetConsent()` to see the form again.
    ///
    /// - Parameters:
    ///   - geography: Region to simulate, e.g. `.eea` to see the GDPR form outside Europe
    ///   - testDeviceIdentifiers: Test device IDs the UMP SDK prints to the console on a real device
    public static func setConsentDebug(
        geography: ConsentDebugGeography,
        testDeviceIdentifiers: [String] = []
    ) {
        consentDebugSettings = ConsentDebugSettings(
            geography: geography,
            testDeviceIdentifiers: testDeviceIdentifiers
        )
    }
    
    private static var activeConsentDebugSettings: ConsentDebugSettings? {
        #if DEBUG
        return consentDebugSettings
        #else
        return nil
        #endif
    }
    
    // MARK: - Ad Unit ID Accessors (Internal)
    
    /// Returns the appropriate banner ad unit ID based on environment
    static var bannerAdUnitID: String {
        #if DEBUG
        warnIfNotConfigured(_bannerAdUnitID, format: "banner")
        #endif
        if AdConfig.isTestEnvironment {
            return AdConfig.testBannerAdUnitID
        }
        return _bannerAdUnitID ?? AdConfig.testBannerAdUnitID
    }
    
    /// Returns the appropriate interstitial ad unit ID based on environment
    static var interstitialAdUnitID: String {
        #if DEBUG
        warnIfNotConfigured(_interstitialAdUnitID, format: "interstitial")
        #endif
        if AdConfig.isTestEnvironment {
            return AdConfig.testInterstitialAdUnitID
        }
        return _interstitialAdUnitID ?? AdConfig.testInterstitialAdUnitID
    }
    
    /// Returns the appropriate rewarded ad unit ID based on environment
    static var rewardedAdUnitID: String {
        #if DEBUG
        warnIfNotConfigured(_rewardedAdUnitID, format: "rewarded")
        #endif
        if AdConfig.isTestEnvironment {
            return AdConfig.testRewardedAdUnitID
        }
        return _rewardedAdUnitID ?? AdConfig.testRewardedAdUnitID
    }
    
    #if DEBUG
    /// Release builds silently fall back to test ads when a production ID is missing,
    /// so surface it while developing.
    private static func warnIfNotConfigured(_ adUnitID: String?, format: String) {
        guard adUnitID == nil else { return }
        print("⚠️ AdmobKit: No production \(format) ad unit ID configured - App Store builds will show test ads")
    }
    #endif
    
    // MARK: - Initialization
    
    /// Gathers consent if required, then starts the Google Mobile Ads SDK.
    ///
    /// Call this method once at app launch, after calling `configure()`. Users in regions that
    /// require consent (EEA, UK, Switzerland) see the message configured in AdMob's
    /// Privacy & messaging. Ads are requested only after this flow allows it.
    public func initialize() {
        Task { _ = await waitUntilAdsCanBeRequested() }
    }
    
    /// Runs the startup flow if needed and returns whether ads can be requested.
    func waitUntilAdsCanBeRequested() async -> Bool {
        let canRequestAds = await startup.start(debugSettings: Self.activeConsentDebugSettings)
        syncState()
        return canRequestAds
    }
    
    // MARK: - Privacy Options
    
    /// Presents the privacy options form so the user can change their consent choices.
    public func presentPrivacyOptions() async {
        _ = await startup.presentPrivacyOptions()
        syncState()
    }
    
    /// Clears the stored consent so the form appears again on the next launch. Intended for testing.
    public func resetConsent() {
        startup.resetConsent()
        syncState()
    }
    
    private func syncState() {
        if isInitialized != startup.isSDKStarted {
            isInitialized = startup.isSDKStarted
        }
        if isPrivacyOptionsRequired != startup.isPrivacyOptionsRequired {
            isPrivacyOptionsRequired = startup.isPrivacyOptionsRequired
        }
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private static func logInitializationStatus(_ status: InitializationStatus) {
        print("✅ Google Mobile Ads SDK initialized")
        for (adapter, state) in status.adapterStatusesByClassName {
            print("   - \(adapter): \(state.state == .ready ? "Ready" : "Not Ready")")
        }
    }
    #endif
}

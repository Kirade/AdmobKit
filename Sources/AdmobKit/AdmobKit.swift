//
//  AdmobKit.swift
//  AdmobKit
//
//  A reusable AdMob integration library for iOS apps.
//

import Foundation
import GoogleMobileAds

/// Main entry point for AdmobKit configuration and initialization.
///
/// Usage:
/// ```swift
/// // In your App's init
/// AdmobKit.configure(bannerAdUnitID: "ca-app-pub-xxx/yyy")
/// AdmobKit.shared.initialize()
/// ```
@MainActor
public final class AdmobKit {
    
    // MARK: - Singleton
    
    /// Shared instance for SDK operations
    public static let shared = AdmobKit()
    
    // MARK: - Configuration Storage
    
    private static var _bannerAdUnitID: String?
    private static var _interstitialAdUnitID: String?
    private static var _rewardedAdUnitID: String?
    
    // MARK: - Properties
    
    /// Indicates whether the Google Mobile Ads SDK has been initialized
    public private(set) var isInitialized = false
    
    // MARK: - Init
    
    private init() {}
    
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
    
    // MARK: - Ad Unit ID Accessors (Public)
    
    /// Returns the appropriate banner ad unit ID based on environment.
    /// Automatically uses test ads in Debug and TestFlight builds.
    public static var bannerAdUnitID: String {
        if AdConfig.isTestEnvironment {
            return AdConfig.testBannerAdUnitID
        }
        return _bannerAdUnitID ?? AdConfig.testBannerAdUnitID
    }
    
    /// Returns the appropriate interstitial ad unit ID based on environment.
    /// Automatically uses test ads in Debug and TestFlight builds.
    public static var interstitialAdUnitID: String {
        if AdConfig.isTestEnvironment {
            return AdConfig.testInterstitialAdUnitID
        }
        return _interstitialAdUnitID ?? AdConfig.testInterstitialAdUnitID
    }
    
    /// Returns the appropriate rewarded ad unit ID based on environment.
    /// Automatically uses test ads in Debug and TestFlight builds.
    public static var rewardedAdUnitID: String {
        if AdConfig.isTestEnvironment {
            return AdConfig.testRewardedAdUnitID
        }
        return _rewardedAdUnitID ?? AdConfig.testRewardedAdUnitID
    }
    
    // MARK: - Initialization
    
    /// Initialize the Google Mobile Ads SDK.
    ///
    /// Call this method once at app launch, after calling `configure()`.
    public func initialize() {
        guard !isInitialized else { return }
        
        MobileAds.shared.start { [weak self] status in
            Task { @MainActor in
                self?.isInitialized = true
                
                #if DEBUG
                self?.logInitializationStatus(status)
                #endif
            }
        }
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private func logInitializationStatus(_ status: InitializationStatus) {
        print("✅ Google Mobile Ads SDK initialized")
        for (adapter, state) in status.adapterStatusesByClassName {
            print("   - \(adapter): \(state.state.rawValue == 1 ? "Ready" : "Not Ready")")
        }
    }
    #endif
}

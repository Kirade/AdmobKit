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
    
    /// Initialize the Google Mobile Ads SDK.
    ///
    /// Call this method once at app launch, after calling `configure()`.
    public func initialize() {
        guard !isInitialized else { return }
        
        Task {
            let status = await MobileAds.shared.start()
            isInitialized = true
            
            #if DEBUG
            logInitializationStatus(status)
            #endif
        }
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private func logInitializationStatus(_ status: InitializationStatus) {
        print("✅ Google Mobile Ads SDK initialized")
        for (adapter, state) in status.adapterStatusesByClassName {
            print("   - \(adapter): \(state.state == .ready ? "Ready" : "Not Ready")")
        }
    }
    #endif
}

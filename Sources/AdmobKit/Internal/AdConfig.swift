//
//  AdConfig.swift
//  AdmobKit
//
//  Environment detection and test ad unit IDs.
//

import Foundation

/// Internal configuration for environment detection and test ad unit IDs
enum AdConfig {
    
    // MARK: - Google's Official Test Ad Unit IDs
    
    /// Test banner ad unit ID (Google's official test ID)
    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    
    /// Test interstitial ad unit ID (Google's official test ID)
    static let testInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    
    /// Test rewarded ad unit ID (Google's official test ID)
    static let testRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    
    /// Test rewarded interstitial ad unit ID (Google's official test ID)
    static let testRewardedInterstitialAdUnitID = "ca-app-pub-3940256099942544/6978759866"
    
    /// Test native ad unit ID (Google's official test ID)
    static let testNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    
    /// Test app open ad unit ID (Google's official test ID)
    static let testAppOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    
    // MARK: - Environment Detection
    
    /// Determines if current environment should use test ads
    /// - Debug build: Always test
    /// - TestFlight: Test (detected via sandbox receipt)
    /// - App Store: Production
    static var isTestEnvironment: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlightBuild
        #endif
    }
    
    /// Detects TestFlight builds by checking for sandbox receipt
    private static var isTestFlightBuild: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return true // No receipt = assume test environment
        }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
    
    // MARK: - Debug Info
    
    /// Returns current environment description for debugging
    static var environmentDescription: String {
        #if DEBUG
        return "Debug (Test Ads)"
        #else
        return isTestFlightBuild ? "TestFlight (Test Ads)" : "App Store (Production Ads)"
        #endif
    }
}

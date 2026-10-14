//
//  InterstitialAdLoader.swift
//  AdmobKit
//

import Foundation
import GoogleMobileAds

@MainActor
public final class InterstitialAdLoader: NSObject {
    
    private var interstitialAd: InterstitialAd?
    private var dismissCallback: (() -> Void)?
    private var delegateHandler: InterstitialDelegateHandler?
    private var _isLoading: Bool = false
    
    public override init() {
        super.init()
    }
    
    public func loadAd() {
        guard !_isLoading else { return }
        
        _isLoading = true
        
        let adUnitID = AdmobKit.interstitialAdUnitID
        
        #if DEBUG
        print("🔄 AdmobKit: Interstitial loading... (adUnitID: \(adUnitID))")
        #endif
        
        Task { [weak self] in
            do {
                let ad = try await InterstitialAd.load(with: adUnitID, request: Request())
                guard let self = self else { return }
                
                self._isLoading = false
                
                #if DEBUG
                print("✅ AdmobKit: Interstitial loaded successfully")
                #endif
                
                self.interstitialAd = ad
                self.delegateHandler = InterstitialDelegateHandler(loader: self)
                self.interstitialAd?.fullScreenContentDelegate = self.delegateHandler
            } catch {
                self?._isLoading = false
                
                #if DEBUG
                print("❌ AdmobKit: Interstitial failed - \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    public func showAd(from viewController: UIViewController, onDismiss: @escaping () -> Void) {
        guard let ad = interstitialAd else {
            #if DEBUG
            print("⚠️ AdmobKit: Interstitial not ready, skipping")
            #endif
            onDismiss()
            return
        }
        
        #if DEBUG
        print("🎬 AdmobKit: Presenting interstitial")
        #endif
        
        self.dismissCallback = onDismiss
        ad.present(from: viewController)
    }
    
    fileprivate func handleAdDismissed() {
        #if DEBUG
        print("👋 AdmobKit: Interstitial dismissed")
        #endif
        
        interstitialAd = nil
        delegateHandler = nil
        dismissCallback?()
        dismissCallback = nil
        loadAd()
    }
}

// MARK: - Delegate Handler

private final class InterstitialDelegateHandler: NSObject, FullScreenContentDelegate {
    
    private weak var loader: InterstitialAdLoader?
    
    init(loader: InterstitialAdLoader) {
        self.loader = loader
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("❌ AdmobKit: Interstitial failed to present - \(error.localizedDescription)")
        #endif
        Task { @MainActor in
            loader?.handleAdDismissed()
        }
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            loader?.handleAdDismissed()
        }
    }
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("📊 AdmobKit: Interstitial impression recorded")
        #endif
    }
    
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("👆 AdmobKit: Interstitial clicked")
        #endif
    }
}

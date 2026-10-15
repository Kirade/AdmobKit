//
//  InterstitialAdLoader.swift
//  AdmobKit
//

import Foundation
import GoogleMobileAds

@MainActor
public final class InterstitialAdLoader: NSObject {
    
    // MARK: - Dependencies
    
    private let waitUntilAdsCanBeRequested: @MainActor () async -> Bool
    private let fetchAd: @MainActor (String) async throws -> PresentableAd
    private let sleepFor: @MainActor (TimeInterval) async -> Void
    private let now: @MainActor () -> Date
    
    // MARK: - Properties
    
    private var interstitialAd: PresentableAd?
    private var loadedAt: Date?
    private var delegateHandler: InterstitialDelegateHandler?
    private var dismissCallbacks = DismissCallbacks()
    private var isPresenting = false
    private var _isLoading = false
    private var retryBackoff = RetryBackoff()
    private var retryTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    
    // MARK: - Init
    
    public override convenience init() {
        self.init(
            waitUntilAdsCanBeRequested: { await AdmobKit.shared.waitUntilAdsCanBeRequested() },
            loadAd: { adUnitID in try await InterstitialAd.load(with: adUnitID, request: Request()) },
            sleep: { delay in try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) },
            now: { Date() }
        )
    }
    
    init(
        waitUntilAdsCanBeRequested: @escaping @MainActor () async -> Bool,
        loadAd: @escaping @MainActor (String) async throws -> PresentableAd,
        sleep: @escaping @MainActor (TimeInterval) async -> Void,
        now: @escaping @MainActor () -> Date
    ) {
        self.waitUntilAdsCanBeRequested = waitUntilAdsCanBeRequested
        self.fetchAd = loadAd
        self.sleepFor = sleep
        self.now = now
        super.init()
    }
    
    deinit {
        retryTask?.cancel()
        expiryTask?.cancel()
    }
    
    // MARK: - Loading
    
    /// Preloads an interstitial. Waits for consent and SDK start-up, and retries failed
    /// loads 5 times with growing delays (5, 10, 20, 40, 60 seconds).
    ///
    /// Does nothing while a load is in flight, an ad is ready, or a retry is pending.
    public func loadAd() {
        guard !_isLoading, interstitialAd == nil, retryTask == nil else { return }
        
        retryBackoff.reset()
        startLoading()
    }
    
    private func startLoading() {
        guard !_isLoading, interstitialAd == nil else { return }
        
        retryTask = nil
        _isLoading = true
        
        Task { [weak self, waitUntilAdsCanBeRequested] in
            guard await waitUntilAdsCanBeRequested() else {
                self?._isLoading = false
                return
            }
            await self?.requestAd()
        }
    }
    
    private func requestAd() async {
        let adUnitID = AdmobKit.interstitialAdUnitID
        
        #if DEBUG
        print("🔄 AdmobKit: Interstitial loading... (adUnitID: \(adUnitID))")
        #endif
        
        do {
            let ad = try await fetchAd(adUnitID)
            _isLoading = false
            retryBackoff.reset()
            
            #if DEBUG
            print("✅ AdmobKit: Interstitial loaded successfully")
            #endif
            
            interstitialAd = ad
            loadedAt = now()
            delegateHandler = InterstitialDelegateHandler(loader: self)
            ad.fullScreenContentDelegate = delegateHandler
            scheduleExpiryRefresh()
        } catch {
            _isLoading = false
            
            #if DEBUG
            print("❌ AdmobKit: Interstitial failed - \(error.localizedDescription)")
            #endif
            
            scheduleRetry()
        }
    }
    
    private func scheduleRetry() {
        guard let delay = retryBackoff.nextDelay() else {
            #if DEBUG
            print("⏸️ AdmobKit: Interstitial retries exhausted until the next loadAd() or showAd()")
            #endif
            return
        }
        
        #if DEBUG
        print("⏳ AdmobKit: Retrying interstitial in \(Int(delay))s")
        #endif
        
        retryTask = Task { [weak self, sleepFor] in
            await sleepFor(delay)
            guard !Task.isCancelled else { return }
            self?.startLoading()
        }
    }
    
    // MARK: - Expiry
    
    private func scheduleExpiryRefresh() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self, sleepFor] in
            await sleepFor(AdFreshness.lifetime)
            guard !Task.isCancelled else { return }
            self?.refreshExpiredAd()
        }
    }
    
    private func refreshExpiredAd() {
        guard !isPresenting, interstitialAd != nil else { return }
        
        #if DEBUG
        print("⌛ AdmobKit: Interstitial expired, reloading")
        #endif
        
        clearAd()
        loadAd()
    }
    
    private func clearAd() {
        interstitialAd = nil
        loadedAt = nil
        delegateHandler = nil
        expiryTask?.cancel()
        expiryTask = nil
    }
    
    // MARK: - Presenting
    
    /// Presents the interstitial if one is ready.
    ///
    /// - Parameters:
    ///   - viewController: View controller to present from. `nil` uses the top view controller.
    ///   - onDismiss: Called after the ad closes, or immediately if no ad is ready.
    public func showAd(from viewController: UIViewController? = nil, onDismiss: @escaping () -> Void) {
        if isPresenting {
            dismissCallbacks.append(onDismiss)
            return
        }
        
        if let loadedAt = loadedAt, AdFreshness.isExpired(loadedAt: loadedAt, now: now()) {
            #if DEBUG
            print("⌛ AdmobKit: Interstitial expired before showing")
            #endif
            clearAd()
        }
        
        guard let ad = interstitialAd else {
            #if DEBUG
            print("⚠️ AdmobKit: Interstitial not ready, skipping")
            #endif
            onDismiss()
            loadAd()
            return
        }
        
        do {
            try ad.canPresent(from: viewController)
        } catch {
            #if DEBUG
            print("⚠️ AdmobKit: Interstitial cannot be presented - \(error.localizedDescription)")
            #endif
            clearAd()
            onDismiss()
            loadAd()
            return
        }
        
        #if DEBUG
        print("🎬 AdmobKit: Presenting interstitial")
        #endif
        
        isPresenting = true
        expiryTask?.cancel()
        expiryTask = nil
        dismissCallbacks.append(onDismiss)
        ad.present(from: viewController)
    }
    
    fileprivate func handleAdDismissed() {
        #if DEBUG
        print("👋 AdmobKit: Interstitial dismissed")
        #endif
        
        isPresenting = false
        clearAd()
        let callbacks = dismissCallbacks.drain()
        loadAd()
        callbacks.forEach { $0() }
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

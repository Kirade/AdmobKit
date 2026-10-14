//
//  AdsStartupCoordinator.swift
//  AdmobKit
//
//  Runs consent gathering and SDK start-up in the order Google requires.
//

import Foundation

/// Runs "update consent info → wait for a window → present the form if required →
/// start the SDK only if ads can be requested" once, and shares the result.
@MainActor
final class AdsStartupCoordinator {
    
    // MARK: - Dependencies
    
    private let consent: ConsentGateway
    private let startSDK: @MainActor () async -> Void
    private let waitForWindow: @MainActor () async -> Void
    
    // MARK: - State
    
    private var startupTask: Task<Bool, Never>?
    private var sdkStartTask: Task<Void, Never>?
    private var sdkStartWaiters: [CheckedContinuation<Void, Never>] = []
    
    /// Whether the Google Mobile Ads SDK finished starting.
    private(set) var isSDKStarted = false
    
    /// Whether the app must offer this user a privacy options entry point.
    private(set) var isPrivacyOptionsRequired = false
    
    // MARK: - Init
    
    init(
        consent: ConsentGateway,
        startSDK: @escaping @MainActor () async -> Void,
        waitForWindow: @escaping @MainActor () async -> Void
    ) {
        self.consent = consent
        self.startSDK = startSDK
        self.waitForWindow = waitForWindow
    }
    
    // MARK: - Startup
    
    /// Runs the startup flow if needed and returns whether ads can be requested.
    /// Repeated and concurrent calls share a single run.
    func start(debugSettings: ConsentDebugSettings?) async -> Bool {
        if let startupTask = startupTask {
            let canRequestAds = await startupTask.value
            return canRequestAds || isSDKStarted
        }
        
        let task = Task { await runStartup(debugSettings: debugSettings) }
        startupTask = task
        return await task.value
    }
    
    /// Runs the startup flow if needed, then suspends until the SDK has started. If ads are not
    /// allowed yet, this keeps waiting until the user allows them through the privacy options form.
    func waitUntilSDKStarted(debugSettings: ConsentDebugSettings?) async {
        guard await !start(debugSettings: debugSettings) else { return }
        await withCheckedContinuation { continuation in
            if isSDKStarted {
                continuation.resume()
            } else {
                sdkStartWaiters.append(continuation)
            }
        }
    }
    
    // MARK: - Privacy Options
    
    /// Presents the privacy options form, then starts the SDK if the user's choice now allows ads.
    func presentPrivacyOptions() async -> Bool {
        do {
            try await consent.presentPrivacyOptions()
        } catch {
            log("Privacy options form failed - \(error.localizedDescription)")
        }
        return await startSDKIfAllowed()
    }
    
    /// Clears stored consent. Takes effect on the next app launch.
    func resetConsent() {
        consent.reset()
        isPrivacyOptionsRequired = consent.isPrivacyOptionsRequired
    }
    
    // MARK: - Private
    
    private func runStartup(debugSettings: ConsentDebugSettings?) async -> Bool {
        do {
            try await consent.requestUpdate(debugSettings: debugSettings)
        } catch {
            log("Consent info update failed - \(error.localizedDescription)")
        }
        
        await waitForWindow()
        
        do {
            try await consent.loadAndPresentIfRequired()
        } catch {
            log("Consent form failed - \(error.localizedDescription)")
        }
        
        return await startSDKIfAllowed()
    }
    
    private func startSDKIfAllowed() async -> Bool {
        isPrivacyOptionsRequired = consent.isPrivacyOptionsRequired
        guard consent.canRequestAds else {
            log("Ads cannot be requested until the user's consent allows it")
            return false
        }
        
        if let sdkStartTask = sdkStartTask {
            await sdkStartTask.value
        } else {
            let task = Task { await startSDK() }
            sdkStartTask = task
            await task.value
        }
        isSDKStarted = true
        
        let waiters = sdkStartWaiters
        sdkStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return true
    }
    
    private func log(_ message: String) {
        #if DEBUG
        print("⚠️ AdmobKit: \(message)")
        #endif
    }
}

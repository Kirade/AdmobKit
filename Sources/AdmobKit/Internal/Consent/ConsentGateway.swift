//
//  ConsentGateway.swift
//  AdmobKit
//
//  Consent operations backed by Google's User Messaging Platform SDK.
//

import Foundation
import UserMessagingPlatform

/// Consent operations AdmobKit needs from a consent management platform.
@MainActor
protocol ConsentGateway {
    var canRequestAds: Bool { get }
    var isPrivacyOptionsRequired: Bool { get }
    func requestUpdate(debugSettings: ConsentDebugSettings?) async throws
    func loadAndPresentIfRequired() async throws
    func presentPrivacyOptions() async throws
    func reset()
}

/// `ConsentGateway` backed by the Google UMP SDK.
@MainActor
final class UMPConsentGateway: ConsentGateway {

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func requestUpdate(debugSettings: ConsentDebugSettings?) async throws {
        let parameters = RequestParameters()
        if let debugSettings = debugSettings {
            let debug = DebugSettings()
            debug.geography = debugSettings.geography.umpGeography
            debug.testDeviceIdentifiers = debugSettings.testDeviceIdentifiers
            parameters.debugSettings = debug
        }
        try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
    }

    func loadAndPresentIfRequired() async throws {
        try await ConsentForm.loadAndPresentIfRequired(from: nil)
    }

    func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: nil)
    }

    func reset() {
        ConsentInformation.shared.reset()
    }
}

// MARK: - UMP Mapping

private extension ConsentDebugGeography {
    var umpGeography: DebugGeography {
        switch self {
        case .eea: return .EEA
        case .regulatedUSState: return .regulatedUSState
        case .other: return .other
        }
    }
}

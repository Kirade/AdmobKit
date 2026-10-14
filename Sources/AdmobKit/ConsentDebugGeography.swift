//
//  ConsentDebugGeography.swift
//  AdmobKit
//
//  Region simulation for testing the consent flow.
//

import Foundation

/// Region to simulate when testing the consent flow in Debug builds.
public enum ConsentDebugGeography: Sendable {
    /// European Economic Area, UK, and Switzerland: the GDPR consent form appears.
    case eea
    /// A regulated US state.
    case regulatedUSState
    /// A region without consent regulation: no form appears.
    case other
}

/// Debug settings passed to the consent info update.
struct ConsentDebugSettings: Equatable {
    var geography: ConsentDebugGeography
    var testDeviceIdentifiers: [String]
}

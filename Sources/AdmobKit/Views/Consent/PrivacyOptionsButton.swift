//
//  PrivacyOptionsButton.swift
//  AdmobKit
//
//  Privacy options entry point that appears only when required.
//

import SwiftUI

/// A button that opens the privacy options form. It renders only for users who must be
/// offered one (for example, users in the EEA), so it can sit in any settings screen.
///
/// Usage:
/// ```swift
/// PrivacyOptionsButton {
///     Text("Privacy Settings")
/// }
/// ```
public struct PrivacyOptionsButton<Label: View>: View {
    
    @ObservedObject private var admobKit = AdmobKit.shared
    private let label: Label
    
    public init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }
    
    public var body: some View {
        if admobKit.isPrivacyOptionsRequired {
            Button {
                Task { await admobKit.presentPrivacyOptions() }
            } label: {
                label
            }
        }
    }
}

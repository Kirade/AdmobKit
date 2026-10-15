//
//  DemoApp.swift
//  AdmobKitDemo
//
//  Reference integration of AdmobKit, also used to verify changes in the simulator.
//
//  Launch arguments (Debug builds):
//    -geography eea|us|other   Simulate a consent region
//    -reset                    Clear stored consent so the form appears again
//    -autoShowInterstitial     Show an interstitial 15 seconds after launch
//

import SwiftUI
import AdmobKit

@main
struct DemoApp: App {
    
    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-geography"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "eea": AdmobKit.setConsentDebug(geography: .eea)
            case "us": AdmobKit.setConsentDebug(geography: .regulatedUSState)
            default: AdmobKit.setConsentDebug(geography: .other)
            }
        }
        if arguments.contains("-reset") {
            AdmobKit.shared.resetConsent()
        }
        #endif
        
        // A real app passes its production ad unit IDs here; Debug builds always show test ads.
        AdmobKit.configure()
        AdmobKit.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    
    @State private var interstitial = InterstitialAdLoader()
    @State private var dismissCount = 0
    @ObservedObject private var admobKit = AdmobKit.shared
    
    var body: some View {
        VStack(spacing: 16) {
            Text("AdmobKit Demo")
                .font(.title)
            
            Text("SDK started: \(admobKit.isInitialized ? "yes" : "no")")
                .accessibilityIdentifier("sdkStatus")
            Text("Privacy options required: \(admobKit.isPrivacyOptionsRequired ? "yes" : "no")")
                .accessibilityIdentifier("privacyStatus")
            
            PrivacyOptionsButton {
                Text("Privacy Settings")
            }
            .accessibilityIdentifier("privacySettings")
            
            Button("Show Interstitial") {
                interstitial.showAd {
                    dismissCount += 1
                }
            }
            .accessibilityIdentifier("showInterstitial")
            
            Text("Interstitial finished: \(dismissCount)")
                .accessibilityIdentifier("interstitialCount")
            
            Spacer()
            
            AdBannerView(size: .adaptive)
                .accessibilityIdentifier("banner")
        }
        .padding(.top, 40)
        .onAppear {
            interstitial.loadAd()
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-autoShowInterstitial") else { return }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            interstitial.showAd {
                dismissCount += 1
            }
        }
    }
}

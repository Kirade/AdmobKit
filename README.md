# AdmobKit

A reusable Swift Package for Google AdMob integration in iOS apps.

## Features

- **Simple API**: Configure once, use everywhere
- **Automatic Environment Detection**: Uses test ads in Debug/TestFlight, production ads in App Store
- **GDPR Consent (UMP)**: Gathers consent where required before any ad is requested
- **SwiftUI First**: Native SwiftUI banner view with smooth animations, standard or adaptive size
- **Interstitial Ads**: Preloads, retries failed loads, and refreshes ads before they expire

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 16.0+ (App Store submissions require Xcode 26)
- Google Mobile Ads SDK 13.x and Google UMP SDK 3.x (resolved automatically)

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kirade/AdmobKit.git", from: "2.1.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/Kirade/AdmobKit.git`
3. Select version and add to your target

## Setup

### 1. Configure Info.plist

Add your AdMob App ID to your app's `Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy</string>
```

Add SKAdNetwork identifiers (required for iOS 14+):

```xml
<key>SKAdNetworkItems</key>
<array>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>cstr6suwn9.skadnetwork</string>
    </dict>
    <!-- Add more as needed -->
</array>
```

Copy the full, up-to-date identifier list from Google's [Update your Info.plist](https://developers.google.com/admob/ios/quick-start#update_your_infoplist) guide.

### 2. Create Consent Messages in AdMob

AdmobKit shows the consent messages you publish in the AdMob console, so each app needs them there:

1. In AdMob, open **Privacy & messaging**.
2. Create and publish a **European regulations** (GDPR) message for the app. Users in the EEA, UK, and Switzerland see it on first launch. Without it, nobody sees a consent form, and those regions only receive Limited Ads.
3. Optional: an **IDFA explainer** message is shown to iOS users in every region before the App Tracking Transparency prompt. It only appears if your `Info.plist` has `NSUserTrackingUsageDescription`:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

### 3. Initialize in App

```swift
import SwiftUI
import AdmobKit

@main
struct MyApp: App {
    
    init() {
        // Configure with your production ad unit IDs
        AdmobKit.configure(
            bannerAdUnitID: "ca-app-pub-xxxxxxxx/yyyyyyyy",
            interstitialAdUnitID: "ca-app-pub-xxxxxxxx/zzzzzzzz"
        )
        
        // Gather consent where required, then start the SDK
        AdmobKit.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`initialize()` updates the user's consent information, waits for your first window, shows the consent form if the user's region requires it, and starts the Google Mobile Ads SDK only once ads may be requested. Banners and interstitials wait for this before loading. If you forget to call it, the first ad request runs it for you.

### 4. Add a Privacy Settings Button

Users who were asked for consent must be able to change their choice later. Put `PrivacyOptionsButton` in your settings screen; it only renders for users who need it:

```swift
import SwiftUI
import AdmobKit

struct SettingsView: View {
    var body: some View {
        List {
            PrivacyOptionsButton {
                Text("Privacy Settings")
            }
        }
    }
}
```

For a custom UI, observe `AdmobKit.shared.isPrivacyOptionsRequired` and call `await AdmobKit.shared.presentPrivacyOptions()`.

### 5. Display Banner Ads

```swift
import SwiftUI
import AdmobKit

struct ContentView: View {
    var body: some View {
        VStack {
            // Your content
            Text("Hello, World!")
            
            Spacer()
            
            // Banner ad at bottom
            AdBannerView()
        }
    }
}
```

Use `AdBannerView(size: .adaptive)` for a large anchored adaptive banner. It fills the available width and is 50 to 150 points tall, so check that your layout leaves room for it.

### 6. Display Interstitial Ads

```swift
import SwiftUI
import AdmobKit

struct GameView: View {
    @State private var interstitial = InterstitialAdLoader()
    
    var body: some View {
        Button("Next Level") {
            interstitial.showAd {
                // Continue here - called after dismissal, or immediately if no ad is ready
            }
        }
        .onAppear {
            interstitial.loadAd()
        }
    }
}
```

## Testing Consent

Simulate a region in Debug builds to test the consent flow from anywhere. The settings are ignored in Release builds.

```swift
init() {
    #if DEBUG
    AdmobKit.setConsentDebug(geography: .eea)  // .eea, .regulatedUSState, or .other
    AdmobKit.shared.resetConsent()             // Show the form again on every launch
    #endif
    AdmobKit.configure(bannerAdUnitID: "ca-app-pub-xxxxxxxx/yyyyyyyy")
    AdmobKit.shared.initialize()
}
```

Simulators apply the simulated region automatically. On a real device, run once, copy the test device ID the UMP SDK prints to the Xcode console, and pass it as `testDeviceIdentifiers:`.

## Example App

[`Examples/AdmobKitDemo.swiftpm`](Examples/AdmobKitDemo.swiftpm) is a minimal SwiftUI app that integrates AdmobKit from this checkout with Google's sample app ID. Open it in Xcode to see consent, adaptive banners, and interstitials working, and switch scenarios with launch arguments (`-geography eea|us|other`, `-reset`, `-autoShowInterstitial`). See its README for details.

## Environment Detection

AdmobKit automatically detects your environment and uses the appropriate ads:

| Environment | Detection Method | Ad Type |
|-------------|------------------|---------|
| Xcode Debug | `#if DEBUG` | Test Ads |
| TestFlight | Sandbox Receipt | Test Ads |
| App Store | Production Receipt | Production Ads |

**You don't need to manually switch between test and production ads!**

## API Reference

### AdmobKit

```swift
// Configure ad unit IDs (call once at app launch)
AdmobKit.configure(
    bannerAdUnitID: String?,        // Your production banner ID
    interstitialAdUnitID: String?,  // Your production interstitial ID
    rewardedAdUnitID: String?       // Your production rewarded ID
)

// Gather consent where required, then start the Google Mobile Ads SDK
AdmobKit.shared.initialize()

// Observable state (AdmobKit is an ObservableObject)
AdmobKit.shared.isInitialized             // SDK started, ads can be requested
AdmobKit.shared.isPrivacyOptionsRequired  // Show a privacy settings entry point

// Let the user change their consent choices
await AdmobKit.shared.presentPrivacyOptions()

// Testing only
AdmobKit.setConsentDebug(geography: .eea, testDeviceIdentifiers: [])  // Debug builds only
AdmobKit.shared.resetConsent()                                        // Takes effect on next launch
```

### PrivacyOptionsButton

```swift
// Renders only for users who must be offered privacy options
PrivacyOptionsButton { Text("Privacy Settings") }
```

### AdBannerView

```swift
AdBannerView()                  // Standard 320x50
AdBannerView(size: .adaptive)   // Large anchored adaptive: full width, 50-150pt tall
```

The banner view:
- Waits for consent and SDK start-up before loading
- Animates in when an ad loads and hides when loading fails
- Adaptive banners request a new ad when the available width changes (rotation, split view)

### InterstitialAdLoader

```swift
let interstitial = InterstitialAdLoader()

// Preload an ad (no-op while a load is in flight, an ad is ready, or a retry is pending)
interstitial.loadAd()

// Present the ad from the top view controller (or pass `from: viewController`);
// onDismiss runs after dismissal, or immediately if no ad can be shown
interstitial.showAd { }
```

The loader:
- Waits for consent and SDK start-up before loading
- Retries a failed load up to 5 times (after 5, 10, 20, 40, and 60 seconds); calling `loadAd()` again while a retry is pending keeps that schedule
- Replaces an unshown ad after 55 minutes, before Google's one-hour expiry
- Checks that the ad can be presented first; if not, skips it and loads a new one
- Preloads the next ad automatically after each dismissal
- Calls every `onDismiss` passed while an ad is on screen once it closes

## Upgrading

### From 2.1.0 to 2.1.1

No code changes are required. `loadAd()` no longer restarts a pending retry immediately, so calling it from `.onAppear` does not send extra ad requests while loads are failing.

### From 2.0 to 2.1

No code changes are required. After updating:

- Create the consent messages described in [Setup step 2](#2-create-consent-messages-in-admob).
- Add `PrivacyOptionsButton` to your settings screen.
- Ads now load only after `initialize()` has gathered consent, so the first ad may appear slightly later than before.

### From 1.x to 2.x

2.0 has no AdmobKit API changes. It moves the underlying Google Mobile Ads SDK from 12.x to 13.x ([v12 is deprecated in Q1 2027 and sunset in Q2 2028](https://developers.google.com/admob/ios/deprecation)).

- Change your dependency rule to `from: "2.1.0"` - an "Up to Next Major Version" rule starting at 1.x will not pick up 2.x.
- If you use mediation adapters, update them to versions compatible with Google Mobile Ads SDK 13.
- See Google's [v12 → v13 migration guide](https://developers.google.com/admob/ios/migration#migrate-to-sdk-v13) if your app also calls the SDK directly.

## Roadmap

- [x] Interstitial Ads
- [x] Adaptive Banner Sizes
- [x] GDPR Consent (UMP)
- [ ] Rewarded Ads
- [ ] Rewarded Interstitial Ads
- [ ] Native Ads
- [ ] App Open Ads

## License

MIT License

## Author

[Kirade](https://github.com/Kirade)

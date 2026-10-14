# AdmobKit

A reusable Swift Package for Google AdMob integration in iOS apps.

## Features

- **Simple API**: Configure once, use everywhere
- **Automatic Environment Detection**: Uses test ads in Debug/TestFlight, production ads in App Store
- **SwiftUI First**: Native SwiftUI banner view with smooth animations
- **Interstitial Ads**: Load/show helper that preloads the next ad after each dismissal

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 16.0+ (App Store submissions require Xcode 26)
- Google Mobile Ads SDK 13.x (resolved automatically)

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kirade/AdmobKit.git", from: "2.0.0")
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

### 2. Initialize in App

```swift
import SwiftUI
import AdmobKit

@main
struct MyApp: App {
    
    init() {
        // Configure with your production ad unit IDs
        AdmobKit.configure(
            bannerAdUnitID: "ca-app-pub-xxxxxxxx/yyyyyyyy"
        )
        
        // Initialize the SDK
        AdmobKit.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 3. Display Banner Ads

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

### 4. Display Interstitial Ads

```swift
import SwiftUI
import AdmobKit

struct GameView: View {
    @State private var interstitial = InterstitialAdLoader()
    
    var body: some View {
        Button("Next Level") {
            guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                .first else { return }
            
            interstitial.showAd(from: rootViewController) {
                // Continue here - called after dismissal, or immediately if no ad is ready
            }
        }
        .onAppear {
            interstitial.loadAd()
        }
    }
}
```

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

// Initialize the Google Mobile Ads SDK
AdmobKit.shared.initialize()

// Check initialization status
AdmobKit.shared.isInitialized  // Bool
```

### AdBannerView

```swift
// Simple banner view - just add to your SwiftUI hierarchy
AdBannerView()
```

The banner view:
- Automatically loads ads when visible
- Animates in/out smoothly
- Hides when ad fails to load
- Uses standard banner size (320x50)

### InterstitialAdLoader

```swift
let interstitial = InterstitialAdLoader()

// Preload an ad (no-op while a load is in flight)
interstitial.loadAd()

// Present the ad; onDismiss runs after dismissal, or immediately if no ad is ready
interstitial.showAd(from: viewController, onDismiss: { })
```

The loader:
- Preloads the next ad automatically after each dismissal
- Does not retry after a failed load - call `loadAd()` again to retry

## Migrating from 1.x

2.0 has no AdmobKit API changes. It moves the underlying Google Mobile Ads SDK from 12.x to 13.x ([v12 is deprecated in Q1 2027 and sunset in Q2 2028](https://developers.google.com/admob/ios/deprecation)).

- Change your dependency rule to `from: "2.0.0"` - an "Up to Next Major Version" rule starting at 1.x will not pick up 2.0.
- If you use mediation adapters, update them to versions compatible with Google Mobile Ads SDK 13.
- See Google's [v12 → v13 migration guide](https://developers.google.com/admob/ios/migration#migrate-to-sdk-v13) if your app also calls the SDK directly.

## Roadmap

- [x] Interstitial Ads
- [ ] Rewarded Ads
- [ ] Rewarded Interstitial Ads
- [ ] Native Ads
- [ ] App Open Ads
- [ ] Adaptive Banner Sizes

## License

MIT License

## Author

[Kirade](https://github.com/Kirade)

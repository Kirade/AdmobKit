# AdmobKit

A reusable Swift Package for Google AdMob integration in iOS apps.

## Features

- **Simple API**: Configure once, use everywhere
- **Automatic Environment Detection**: Uses test ads in Debug/TestFlight, production ads in App Store
- **SwiftUI First**: Native SwiftUI banner view with smooth animations
- **Future-Proof**: Ready for interstitial, rewarded, and other ad formats

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kirade/AdmobKit.git", from: "1.0.0")
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

## Roadmap

- [ ] Interstitial Ads
- [ ] Rewarded Ads
- [ ] Rewarded Interstitial Ads
- [ ] Native Ads
- [ ] App Open Ads
- [ ] Adaptive Banner Sizes

## License

MIT License

## Author

[Kirade](https://github.com/Kirade)

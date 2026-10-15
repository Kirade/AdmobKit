# ADMOBKIT KNOWLEDGE BASE

**Updated:** 2026-10-15
**Branch:** main

## OVERVIEW

Swift Package wrapping Google AdMob for iOS. SwiftUI-first, auto-switches test/production ads based on environment, and gathers GDPR consent through Google's UMP SDK before any ad is requested.

## STRUCTURE

```
AdmobKit/
├── .github/
│   ├── dependabot.yml           # Monthly: GitHub Actions + GoogleMobileAds major bumps
│   └── workflows/
│       ├── ci.yml               # Build (Swift 5 mode) + Swift 6 strict concurrency check + unit tests
│       └── release.yml          # On `v*` tag: build, then publish GitHub Release
├── Sources/AdmobKit/
│   ├── AdmobKit.swift           # Entry point: configure() + initialize() + privacy options
│   ├── ConsentDebugGeography.swift  # Public debug region enum + internal debug settings
│   ├── Internal/
│   │   ├── AdConfig.swift       # Environment detection, test ad unit IDs
│   │   ├── AdFreshness.swift    # 55-minute expiry rule for loaded full-screen ads
│   │   ├── BannerRequestTracker.swift  # When a banner needs a new request (width changes)
│   │   ├── RetryBackoff.swift   # 5/10/20/40/60s retry delays
│   │   └── Consent/
│   │       ├── AdsStartupCoordinator.swift  # consent update → window → form → SDK start, once
│   │       ├── ConsentGateway.swift         # Consent protocol + UMP implementation
│   │       └── KeyWindow.swift              # Waits for a key window before showing the form
│   └── Views/
│       ├── Banner/
│       │   └── AdBannerView.swift       # SwiftUI banner (standard / adaptive)
│       ├── Consent/
│       │   └── PrivacyOptionsButton.swift   # Shows only when privacy options are required
│       └── Interstitial/
│           ├── DismissCallbacks.swift       # onDismiss callbacks queued while an ad is shown
│           ├── InterstitialAdLoader.swift   # Full-screen ad manager (injectable load/sleep/clock)
│           └── PresentableAd.swift          # Protocol over InterstitialAd so tests can use fakes
├── Tests/AdmobKitTests/         # XCTest: coordinator + loader (fakes in *TestDoubles / Fake*.swift) + pure helpers
├── scripts/
│   └── simulator-destination.sh # Picks an available iPhone simulator for `xcodebuild test`
├── docs/superpowers/            # Design spec and implementation plan for 2.1.0
├── Package.swift                # iOS 15+, swift-tools 5.9, GoogleMobileAds 13.x, UMP 3.x
└── README.md
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new ad format | `Views/` | Create subdir, follow Banner/Interstitial pattern; pass the consent gate before loading (see CONVENTIONS) |
| Change environment logic | `Internal/AdConfig.swift` | Test vs production switching |
| Change consent / start-up order | `Internal/Consent/AdsStartupCoordinator.swift` | Covered by `AdsStartupCoordinatorTests` |
| Add config options | `AdmobKit.swift` | Static configure() method |
| Modify ad unit ID handling | `AdmobKit.swift:117-159` | Accessor properties + DEBUG missing-ID warning |
| Bump GoogleMobileAds | `Package.swift` | Major bump → AdmobKit major release (see NOTES) |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `AdmobKit` | class | AdmobKit.swift:21 | Singleton entry point, `ObservableObject` |
| `AdmobKit.configure()` | static method | AdmobKit.swift:72 | Set production ad unit IDs |
| `AdmobKit.setConsentDebug()` | static method | AdmobKit.swift:99 | Simulate a consent region (Debug builds only) |
| `AdmobKit.shared.initialize()` | method | AdmobKit.swift:168 | Gather consent, then start the SDK |
| `AdmobKit.shared.waitUntilAdsCanBeRequested()` | internal method | AdmobKit.swift:173 | One-shot gate for each ad load (interstitials) |
| `AdmobKit.shared.waitUntilSDKStarted()` | internal method | AdmobKit.swift:181 | Waits until ads are allowed, even later in the session (banners) |
| `AdmobKit.shared.presentPrivacyOptions()` | method | AdmobKit.swift:189 | Privacy options form |
| `AdsStartupCoordinator` | class | Internal/Consent | Runs the consent/start-up flow once |
| `PrivacyOptionsButton` | struct | Views/Consent | Settings-screen entry point |
| `AdBannerView` / `AdBannerSize` | struct / enum | Views/Banner | Drop-in SwiftUI banner, `.standard` or `.adaptive` |
| `InterstitialAdLoader` | class | Views/Interstitial | Load/show interstitials with retry and expiry; internal init injects load/sleep/clock for tests |
| `PresentableAd` | protocol | Views/Interstitial | `canPresent`/`present`/delegate surface; `InterstitialAd` conforms |
| `AdConfig` | enum | Internal/AdConfig.swift | Test IDs + environment detection |

## CONVENTIONS

- **@MainActor**: All public ad classes (AdmobKit, InterstitialAdLoader) and consent types
- **Consent gate**: Never request an ad before the gate opens. Per-request loaders call `await AdmobKit.shared.waitUntilAdsCanBeRequested()` and skip on `false`; views that stay on screen call `await AdmobKit.shared.waitUntilSDKStarted()` so they recover when the user allows ads through privacy options
- **No UMP types in public API**: Wrap them (e.g. `ConsentDebugGeography`) so apps never import UserMessagingPlatform
- **Testable seams**: Keep SDK calls behind small protocols/closures and logic in pure types, as `AdsStartupCoordinator`, `InterstitialAdLoader` (via `PresentableAd` + injected closures), `RetryBackoff`, `AdFreshness`, `DismissCallbacks`, and `BannerRequestTracker` do. Loader tests park sleeps in `FakeSleeper` and call `settle()` to let main-actor tasks run
- **MARK comments**: Divide code into sections (Singleton, Properties, Init, etc.)
- **#if DEBUG**: Wrap ALL print statements
- **Access control**: `public private(set)` for read-only state, `private init()` for singletons
- **Concurrency**: Prefer the SDK's `async` APIs (`await MobileAds.shared.start()`, `try await InterstitialAd.load(...)`) inside a `Task` from `@MainActor` code; for delegate callbacks use `Task { @MainActor in }`
- **Swift 6 clean**: Code must build with `SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete` (enforced in CI), but the manifest stays in Swift 5 mode
- **Indentation**: 4 spaces

## ANTI-PATTERNS (THIS PROJECT)

| Pattern | Why Forbidden |
|---------|---------------|
| Storyboard/XIB init | `fatalError` in `init(coder:)` - SwiftUI only |
| Print without `#if DEBUG` | Logs leak to production |
| Direct test ad unit IDs | Use `AdConfig.testXxxAdUnitID` constants |
| Skip `@MainActor` on ad classes | Google SDK requires main thread |
| Loading ads without the consent gate | Violates Google's "check canRequestAds first" requirement |
| `\|\| true` / piping `xcodebuild` in workflows | Hides build failures - CI went green while unable to fail |
| Hard-coded simulator names in workflows | Device lists change with Xcode; use `scripts/simulator-destination.sh` |
| Bumping `swift-tools-version` to 6.x | Swift 6 mode turns new SDK concurrency annotations in 13.x minors into compile errors in consuming apps |

## UNIQUE STYLES

- **Auto environment detection**: `AdConfig.isTestEnvironment` checks DEBUG flag + sandbox receipt
- **Graceful fallback**: If no production ID configured, falls back to test ads (DEBUG builds print a warning)
- **Delegate handler pattern**: Interstitial uses separate `InterstitialDelegateHandler` class to avoid retain cycles
- **Height animation**: Banner animates height 0 → ad height (50 standard, 50-150 adaptive) on load success

## COMMANDS

```bash
# Build (iOS-only: GoogleMobileAds has no macOS slice, so `swift build` fails)
xcodebuild build -scheme AdmobKit -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -quiet

# Swift 6 strict concurrency check (same as CI)
xcodebuild build -scheme AdmobKit -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -quiet SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete

# Unit tests (same as CI)
xcodebuild test -scheme AdmobKit -destination "$(./scripts/simulator-destination.sh)" -skipPackagePluginValidation -quiet

# Resolve dependencies
swift package resolve

# Open in Xcode
open Package.swift
```

## NOTES

- **Consent flow**: `initialize()` → consent info update → wait for key window (≤3s) → form if required → SDK start only if `canRequestAds`. Failures fall back to the previous session's consent. If ads cannot be requested, the session stays ad-free and retries next launch.
- **AdMob console**: Consent and IDFA forms come from each app's Privacy & messaging messages; without a published GDPR message nobody sees a form. The IDFA message also needs `NSUserTrackingUsageDescription` in the app's Info.plist.
- **Releases**: Push a `vX.Y.Z` tag; `release.yml` builds and publishes the GitHub Release. A GoogleMobileAds major bump ships as an AdmobKit major (2.0.0 = GMA 13), so apps must update their `from:` rule.
- **SDK lifecycle**: Track https://developers.google.com/admob/ios/deprecation - GMA 13 is deprecated Q1 2028, sunset Q2 2029.
- **Package.resolved is gitignored**: Consumers resolve the newest 13.x themselves.
- **Environment detection**: `Bundle.appStoreReceiptURL` is deprecated (Swift, iOS 18) in favor of async `AppTransaction`; still works while the package targets iOS 15.
- **Roadmap items**: Rewarded, Native, App Open ads defined in AdConfig but not implemented yet; `rewardedAdUnitID` is accepted but unused.

# ADMOBKIT KNOWLEDGE BASE

**Generated:** 2026-01-07
**Commit:** 72d6621
**Branch:** main

## OVERVIEW

Swift Package wrapping Google AdMob for iOS. SwiftUI-first, auto-switches test/production ads based on environment.

## STRUCTURE

```
AdmobKit/
├── Sources/AdmobKit/
│   ├── AdmobKit.swift           # Entry point: configure() + initialize()
│   ├── Internal/
│   │   └── AdConfig.swift       # Environment detection, test ad unit IDs
│   └── Views/
│       ├── Banner/
│       │   └── AdBannerView.swift       # SwiftUI banner component
│       └── Interstitial/
│           └── InterstitialAdLoader.swift   # Full-screen ad manager
├── Package.swift                # iOS 15+, Swift 5.9+, GoogleMobileAds 12.0.0
└── README.md
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new ad format | `Views/` | Create subdir, follow Banner/Interstitial pattern |
| Change environment logic | `Internal/AdConfig.swift` | Test vs production switching |
| Add config options | `AdmobKit.swift` | Static configure() method |
| Modify ad unit ID handling | `AdmobKit.swift:74-95` | Accessor properties |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `AdmobKit` | class | AdmobKit.swift:20 | Singleton entry point |
| `AdmobKit.configure()` | static method | AdmobKit.swift:53 | Set production ad unit IDs |
| `AdmobKit.shared.initialize()` | method | AdmobKit.swift:102 | Start Google Mobile Ads SDK |
| `AdBannerView` | struct | Views/Banner | Drop-in SwiftUI banner |
| `InterstitialAdLoader` | class | Views/Interstitial | Load/show interstitials |
| `AdConfig` | enum | Internal/AdConfig.swift | Test IDs + environment detection |

## CONVENTIONS

- **@MainActor**: All public ad classes (AdmobKit, InterstitialAdLoader)
- **MARK comments**: Divide code into sections (Singleton, Properties, Init, etc.)
- **#if DEBUG**: Wrap ALL print statements
- **Access control**: `public private(set)` for read-only state, `private init()` for singletons
- **Concurrency**: Use `Task { @MainActor in }` for completion handler callbacks
- **Indentation**: 4 spaces

## ANTI-PATTERNS (THIS PROJECT)

| Pattern | Why Forbidden |
|---------|---------------|
| Storyboard/XIB init | `fatalError` in `init(coder:)` - SwiftUI only |
| Print without `#if DEBUG` | Logs leak to production |
| Direct test ad unit IDs | Use `AdConfig.testXxxAdUnitID` constants |
| Skip `@MainActor` on ad classes | Google SDK requires main thread |

## UNIQUE STYLES

- **Auto environment detection**: `AdConfig.isTestEnvironment` checks DEBUG flag + sandbox receipt
- **Graceful fallback**: If no production ID configured, falls back to test ads
- **Delegate handler pattern**: Interstitial uses separate `InterstitialDelegateHandler` class to avoid retain cycles
- **Height animation**: Banner animates height 0 → 50 on load success

## COMMANDS

```bash
# Build
swift build

# Resolve dependencies
swift package resolve

# Open in Xcode
open Package.swift
```

## NOTES

- **No tests**: `Tests/` directory missing. `swift test` has nothing to run.
- **No CI**: No GitHub Actions or automation.
- **Empty directory**: `Sources/AdmobKit/Manager/` exists but is empty (WIP or abandoned).
- **Roadmap items**: Rewarded, Native, App Open ads defined in AdConfig but not implemented yet.
- **iOS 15+ only**: Uses modern Swift concurrency features.

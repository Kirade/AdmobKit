# AdmobKitDemo

A minimal SwiftUI app that integrates AdmobKit from this checkout. Use it as a reference integration and to check changes in the simulator.

It uses Google's sample app ID, which has GDPR and IDFA messages configured in AdMob, and shows test ads only.

## Run

Open `Examples/AdmobKitDemo.swiftpm` in Xcode and run it, or from the command line:

```bash
cd Examples/AdmobKitDemo.swiftpm
xcodebuild build -scheme AdmobKitDemo -destination "id=<simulator UDID>" -derivedDataPath .build/dd -skipPackagePluginValidation -quiet
xcrun simctl install <simulator UDID> .build/dd/Build/Products/Debug-iphonesimulator/AdmobKitDemo.app
xcrun simctl launch --console-pty <simulator UDID> com.kirade.admobkitdemo -geography eea -reset
```

`../../scripts/simulator-destination.sh` prints a `id=<UDID>` destination for an available iPhone simulator.

## Scenarios

| Launch arguments | What you should see |
|---|---|
| `-geography eea -reset` | The GDPR consent form. After answering, the adaptive banner and the privacy settings button appear. |
| `-geography other` | No form. SDK starts, then the adaptive banner loads. |
| `-geography other -autoShowInterstitial` | As above, plus a test interstitial 15 seconds after launch. |

Add `NSUserTrackingUsageDescription` to `Info.plist` to see the IDFA explainer and ATT prompt. Without it, UMP skips the IDFA message.

Accessibility identifiers (`sdkStatus`, `privacyStatus`, `privacySettings`, `showInterstitial`, `interstitialCount`, `banner`) are set for UI automation.

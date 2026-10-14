# AdmobKit 2.1.0 (UMP 동의, 적응형 배너, 전면 광고 안정화) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱 코드 변경 없이 2.1.0으로 올리기만 하면 규제 지역 사용자에게 UMP 동의를 받고 그 뒤에만 광고를 요청하며, 적응형 배너(opt-in)와 안정적인 전면 광고를 제공한다.

**Architecture:** `AdsStartupCoordinator`가 "동의 정보 갱신 → 창 대기 → 필요 시 동의 화면 → canRequestAds면 SDK 시작"을 한 번만 실행하고 결과를 공유한다. 배너와 전면 광고는 `AdmobKit.shared.waitUntilAdsCanBeRequested()`를 기다린 뒤 로드한다. 재시도·만료·콜백·배너 너비 판단은 SDK와 분리된 순수 타입으로 만들어 단위 테스트한다.

**Tech Stack:** Swift 5.9 매니페스트(Swift 5 모드, Swift 6 strict 빌드 통과 필수), SwiftUI/UIKit, Google Mobile Ads SDK 13.x, Google UMP SDK 3.x, XCTest, GitHub Actions(macos-15).

**Spec:** `docs/superpowers/specs/2026-10-15-consent-banner-interstitial-design.md`

## Global Constraints

- 배포 타깃 iOS 15.0, `swift-tools-version: 5.9` 유지 (Swift 6 모드로 올리지 않는다).
- 의존성: GMA `from: "13.0.0"`, UMP `from: "3.0.0"` (제품 `GoogleUserMessagingPlatform`, 패키지 `swift-package-manager-google-user-messaging-platform`).
- 공개 API는 추가만 한다. 기존 호출 코드는 수정 없이 컴파일되어야 한다.
- UMP 타입은 공개 API에 드러내지 않는다.
- 모든 `print`는 `#if DEBUG` 안에 둔다. 광고 클래스는 `@MainActor`. 들여쓰기 4칸, `// MARK: -` 구획. 타입 본문 안의 빈 줄은 기존 파일처럼 들여쓰기 공백을 둔다.
- 매 작업 끝에 다음 세 명령이 모두 성공해야 한다:
  - `xcodebuild build -scheme AdmobKit -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -quiet`
  - 같은 명령 + `SWIFT_VERSION=6 SWIFT_STRICT_CONCURRENCY=complete`
  - `xcodebuild test -scheme AdmobKit -destination "$(bash scripts/simulator-destination.sh)" -skipPackagePluginValidation -quiet` (Task 1 이후)
- 릴리스 버전: 2.1.0.

## Review Focus

1. 전면 광고 `onDismiss` 안에서 다시 `showAd`를 부르는 경우 → 배타적 접근 위반으로 크래시 나지 않고 정상 처리되어야 한다. (Task 4 `DismissCallbacksTests.testCallbackCanQueueAnotherWhileDrainedCallbacksRun`)
2. 앱이 1시간 넘게 백그라운드에 있었거나 기기 시계가 뒤로 돌아간 경우 → 오래된 광고를 띄우지 않아야 한다. (Task 4 `AdFreshnessTests`)
3. 첫 실행이 오프라인이라 동의 정보 갱신이 실패하고 이전 동의도 없는 경우 → SDK를 시작하지 않고 광고를 요청하지 않으며, `showAd`는 즉시 `onDismiss`를 호출해야 한다. (Task 2 `testDoesNotStartSDKWhenAdsCannotBeRequested`, `testContinuesWithPreviousConsentWhenUpdateFails`)
4. 첫 레이아웃의 너비가 0이거나 회전·분할 화면으로 너비가 바뀌는 경우 → 쓸 수 있는 새 너비에서만 요청해야 한다. (Task 5 `BannerRequestTrackerTests`)
5. 처음에는 광고 요청이 막혔다가 사용자가 개인정보 설정에서 허용한 경우 → SDK가 한 번만 시작되고 이후 광고가 로드되어야 한다. (Task 2 `testPrivacyOptionsEnablingAdsStartsSDKOnce`)

---

### Task 1: 테스트 기반과 `RetryBackoff`

**Files:**
- Modify: `Package.swift`
- Create: `scripts/simulator-destination.sh`
- Create: `Sources/AdmobKit/Internal/RetryBackoff.swift`
- Create: `Tests/AdmobKitTests/RetryBackoffTests.swift`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `struct RetryBackoff { static let defaultDelays: [TimeInterval]; init(delays:); mutating func nextDelay() -> TimeInterval?; mutating func reset() }`
- Produces: `scripts/simulator-destination.sh` — stdout에 `id=<UDID>` 출력

- [ ] **Step 1: 테스트 타깃 추가** — `Package.swift`의 `targets`에 추가:

```swift
        .testTarget(
            name: "AdmobKitTests",
            dependencies: ["AdmobKit"]
        ),
```

- [ ] **Step 2: 시뮬레이터 선택 스크립트 작성** — `scripts/simulator-destination.sh`:

```bash
#!/bin/bash
# Prints an xcodebuild destination for an available iPhone simulator on the newest iOS runtime,
# so CI and local runs never depend on a hard-coded device name.
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
runtimes = [r for r in devices if ".SimRuntime.iOS-" in r]
runtimes.sort(key=lambda r: [int(part) for part in r.rsplit("iOS-", 1)[1].split("-")])
for runtime in reversed(runtimes):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print("id=" + device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator")
'
```

- [ ] **Step 3: 실패하는 테스트 작성** — `Tests/AdmobKitTests/RetryBackoffTests.swift`:

```swift
import XCTest
@testable import AdmobKit

final class RetryBackoffTests: XCTestCase {
    
    func testDelaysDoubleUpToSixtySecondsThenStop() {
        var backoff = RetryBackoff()
        
        XCTAssertEqual(backoff.nextDelay(), 5)
        XCTAssertEqual(backoff.nextDelay(), 10)
        XCTAssertEqual(backoff.nextDelay(), 20)
        XCTAssertEqual(backoff.nextDelay(), 40)
        XCTAssertEqual(backoff.nextDelay(), 60)
        XCTAssertNil(backoff.nextDelay())
        XCTAssertNil(backoff.nextDelay())
    }
    
    func testResetStartsOverFromFirstDelay() {
        var backoff = RetryBackoff()
        _ = backoff.nextDelay()
        _ = backoff.nextDelay()
        
        backoff.reset()
        
        XCTAssertEqual(backoff.nextDelay(), 5)
    }
}
```

- [ ] **Step 4: 스킴 확인 후 실패 확인** — `xcodebuild -list`로 테스트를 포함한 스킴 이름을 확인한다(예상: `AdmobKit`. 다르면 이 계획과 CI의 `-scheme`을 그 이름으로 바꾼다). 이어서 `xcodebuild test -scheme AdmobKit -destination "$(bash scripts/simulator-destination.sh)" -skipPackagePluginValidation -quiet` 실행. Expected: `cannot find 'RetryBackoff' in scope`로 실패.

- [ ] **Step 5: 구현** — `Sources/AdmobKit/Internal/RetryBackoff.swift`:

```swift
//
//  RetryBackoff.swift
//  AdmobKit
//
//  Delays between retries of a failed ad load.
//

import Foundation

/// Retry delays for failed ad loads: 5, 10, 20, 40, 60 seconds, then give up.
struct RetryBackoff {
    
    static let defaultDelays: [TimeInterval] = [5, 10, 20, 40, 60]
    
    private let delays: [TimeInterval]
    private var attempt = 0
    
    init(delays: [TimeInterval] = RetryBackoff.defaultDelays) {
        self.delays = delays
    }
    
    /// Returns the delay before the next retry, or `nil` once retries are exhausted.
    mutating func nextDelay() -> TimeInterval? {
        guard attempt < delays.count else { return nil }
        defer { attempt += 1 }
        return delays[attempt]
    }
    
    mutating func reset() {
        attempt = 0
    }
}
```

- [ ] **Step 6: 테스트 통과 확인** — Step 4의 test 명령. Expected: PASS.

- [ ] **Step 7: CI에 테스트 단계 추가** — `.github/workflows/ci.yml`의 마지막 단계 뒤에:

```yaml
      - name: Test
        run: |
          xcodebuild test \
            -scheme AdmobKit \
            -destination "$(bash scripts/simulator-destination.sh)" \
            -skipPackagePluginValidation \
            -quiet
```

- [ ] **Step 8: 빌드 2종 확인 후 커밋**

```bash
git add Package.swift scripts/simulator-destination.sh Sources/AdmobKit/Internal/RetryBackoff.swift Tests .github/workflows/ci.yml
git commit -m "test: add test target, simulator picker, and RetryBackoff"
```

---

### Task 2: 동의 게이트웨이와 `AdsStartupCoordinator`

**Files:**
- Modify: `Package.swift` (UMP 의존성)
- Create: `Sources/AdmobKit/ConsentDebugGeography.swift`
- Create: `Sources/AdmobKit/Internal/Consent/ConsentGateway.swift`
- Create: `Sources/AdmobKit/Internal/Consent/AdsStartupCoordinator.swift`
- Create: `Tests/AdmobKitTests/FakeConsentGateway.swift`
- Create: `Tests/AdmobKitTests/AdsStartupCoordinatorTests.swift`

**Interfaces:**
- Produces: `public enum ConsentDebugGeography: Sendable { case eea, regulatedUSState, other }`
- Produces: `struct ConsentDebugSettings: Equatable { var geography: ConsentDebugGeography; var testDeviceIdentifiers: [String] }`
- Produces: `@MainActor protocol ConsentGateway { var canRequestAds: Bool { get }; var isPrivacyOptionsRequired: Bool { get }; func requestUpdate(debugSettings: ConsentDebugSettings?) async throws; func loadAndPresentIfRequired() async throws; func presentPrivacyOptions() async throws; func reset() }`
- Produces: `@MainActor final class UMPConsentGateway: ConsentGateway`
- Produces: `@MainActor final class AdsStartupCoordinator { init(consent:startSDK:waitForWindow:); private(set) var isSDKStarted: Bool; private(set) var isPrivacyOptionsRequired: Bool; func start(debugSettings: ConsentDebugSettings?) async -> Bool; func presentPrivacyOptions() async -> Bool; func resetConsent() }`

- [ ] **Step 1: UMP 의존성 추가** — `Package.swift`:

```swift
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.0.0"
        ),
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git",
            from: "3.0.0"
        )
    ],
```

그리고 `AdmobKit` 타깃 dependencies에 `.product(name: "GoogleUserMessagingPlatform", package: "swift-package-manager-google-user-messaging-platform")` 추가.

- [ ] **Step 2: 디버그 지역 타입** — `Sources/AdmobKit/ConsentDebugGeography.swift`:

```swift
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
```

- [ ] **Step 3: 게이트웨이** — `Sources/AdmobKit/Internal/Consent/ConsentGateway.swift`:

```swift
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
```

- [ ] **Step 4: 가짜 게이트웨이** — `Tests/AdmobKitTests/FakeConsentGateway.swift`:

```swift
@testable import AdmobKit

struct TestError: Error {}

/// Records every consent step so tests can check order and counts.
@MainActor
final class FakeConsentGateway: ConsentGateway {
    
    var canRequestAds = false
    var isPrivacyOptionsRequired = false
    var updateError: Error?
    var formError: Error?
    var privacyOptionsError: Error?
    /// Simulates the user's choice in the consent form.
    var canRequestAdsAfterForm: Bool?
    /// Simulates the user's choice in the privacy options form.
    var canRequestAdsAfterPrivacyOptions: Bool?
    
    private(set) var events: [String] = []
    private(set) var receivedDebugSettings: [ConsentDebugSettings?] = []
    
    func record(_ event: String) {
        events.append(event)
    }
    
    func count(_ event: String) -> Int {
        events.filter { $0 == event }.count
    }
    
    func requestUpdate(debugSettings: ConsentDebugSettings?) async throws {
        record("update")
        receivedDebugSettings.append(debugSettings)
        if let updateError = updateError { throw updateError }
    }
    
    func loadAndPresentIfRequired() async throws {
        record("form")
        if let canRequestAdsAfterForm = canRequestAdsAfterForm { canRequestAds = canRequestAdsAfterForm }
        if let formError = formError { throw formError }
    }
    
    func presentPrivacyOptions() async throws {
        record("privacyOptions")
        if let canRequestAdsAfterPrivacyOptions = canRequestAdsAfterPrivacyOptions {
            canRequestAds = canRequestAdsAfterPrivacyOptions
        }
        if let privacyOptionsError = privacyOptionsError { throw privacyOptionsError }
    }
    
    func reset() {
        record("reset")
        canRequestAds = false
    }
}
```

- [ ] **Step 5: 실패하는 테스트** — `Tests/AdmobKitTests/AdsStartupCoordinatorTests.swift`:

```swift
import XCTest
@testable import AdmobKit

@MainActor
final class AdsStartupCoordinatorTests: XCTestCase {
    
    private func makeCoordinator(_ consent: FakeConsentGateway) -> AdsStartupCoordinator {
        AdsStartupCoordinator(
            consent: consent,
            startSDK: { consent.record("sdkStart") },
            waitForWindow: { consent.record("window") }
        )
    }
    
    func testRunsConsentStepsInOrderBeforeStartingSDK() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertTrue(coordinator.isSDKStarted)
        XCTAssertEqual(consent.events, ["update", "window", "form", "sdkStart"])
    }
    
    func testRepeatedAndConcurrentStartsRunOnce() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        async let first = coordinator.start(debugSettings: nil)
        async let second = coordinator.start(debugSettings: nil)
        let results = await [first, second]
        let third = await coordinator.start(debugSettings: nil)
        
        XCTAssertEqual(results, [true, true])
        XCTAssertTrue(third)
        XCTAssertEqual(consent.count("update"), 1)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testDoesNotStartSDKWhenAdsCannotBeRequested() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertFalse(canRequestAds)
        XCTAssertFalse(coordinator.isSDKStarted)
        XCTAssertEqual(consent.count("sdkStart"), 0)
    }
    
    func testContinuesWithPreviousConsentWhenUpdateFails() async {
        let consent = FakeConsentGateway()
        consent.updateError = TestError()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.events, ["update", "window", "form", "sdkStart"])
    }
    
    func testContinuesWhenConsentFormFails() async {
        let consent = FakeConsentGateway()
        consent.formError = TestError()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testConsentGivenInFormStartsSDK() async {
        let consent = FakeConsentGateway()
        consent.canRequestAdsAfterForm = true
        let coordinator = makeCoordinator(consent)
        
        let canRequestAds = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testPrivacyOptionsEnablingAdsStartsSDKOnce() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        let initiallyAllowed = await coordinator.start(debugSettings: nil)
        consent.canRequestAdsAfterPrivacyOptions = true
        
        let allowedAfterOptions = await coordinator.presentPrivacyOptions()
        let allowedLater = await coordinator.start(debugSettings: nil)
        
        XCTAssertFalse(initiallyAllowed)
        XCTAssertTrue(allowedAfterOptions)
        XCTAssertTrue(allowedLater)
        XCTAssertTrue(coordinator.isSDKStarted)
        XCTAssertEqual(consent.count("sdkStart"), 1)
        XCTAssertEqual(consent.count("update"), 1)
    }
    
    func testPrivacyOptionsFailureKeepsSDKRunning() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        let coordinator = makeCoordinator(consent)
        _ = await coordinator.start(debugSettings: nil)
        consent.privacyOptionsError = TestError()
        
        let canRequestAds = await coordinator.presentPrivacyOptions()
        
        XCTAssertTrue(canRequestAds)
        XCTAssertEqual(consent.count("sdkStart"), 1)
    }
    
    func testReflectsPrivacyOptionsRequirement() async {
        let consent = FakeConsentGateway()
        consent.canRequestAds = true
        consent.isPrivacyOptionsRequired = true
        let coordinator = makeCoordinator(consent)
        
        _ = await coordinator.start(debugSettings: nil)
        
        XCTAssertTrue(coordinator.isPrivacyOptionsRequired)
    }
    
    func testPassesDebugSettingsToConsentUpdate() async {
        let consent = FakeConsentGateway()
        let coordinator = makeCoordinator(consent)
        let settings = ConsentDebugSettings(geography: .eea, testDeviceIdentifiers: ["TEST-DEVICE"])
        
        _ = await coordinator.start(debugSettings: settings)
        
        XCTAssertEqual(consent.receivedDebugSettings, [settings])
    }
}
```

- [ ] **Step 6: 실패 확인** — test 명령. Expected: `cannot find 'AdsStartupCoordinator' in scope`.

- [ ] **Step 7: 구현** — `Sources/AdmobKit/Internal/Consent/AdsStartupCoordinator.swift`:

```swift
//
//  AdsStartupCoordinator.swift
//  AdmobKit
//
//  Runs consent gathering and SDK start-up in the order Google requires.
//

import Foundation

/// Runs "update consent info → wait for a window → present the form if required →
/// start the SDK only if ads can be requested" once, and shares the result.
@MainActor
final class AdsStartupCoordinator {
    
    // MARK: - Dependencies
    
    private let consent: ConsentGateway
    private let startSDK: @MainActor () async -> Void
    private let waitForWindow: @MainActor () async -> Void
    
    // MARK: - State
    
    private var startupTask: Task<Bool, Never>?
    private var sdkStartTask: Task<Void, Never>?
    
    /// Whether the Google Mobile Ads SDK finished starting.
    private(set) var isSDKStarted = false
    
    /// Whether the app must offer this user a privacy options entry point.
    private(set) var isPrivacyOptionsRequired = false
    
    // MARK: - Init
    
    init(
        consent: ConsentGateway,
        startSDK: @escaping @MainActor () async -> Void,
        waitForWindow: @escaping @MainActor () async -> Void
    ) {
        self.consent = consent
        self.startSDK = startSDK
        self.waitForWindow = waitForWindow
    }
    
    // MARK: - Startup
    
    /// Runs the startup flow if needed and returns whether ads can be requested.
    /// Repeated and concurrent calls share a single run.
    func start(debugSettings: ConsentDebugSettings?) async -> Bool {
        if let startupTask = startupTask {
            let canRequestAds = await startupTask.value
            return canRequestAds || isSDKStarted
        }
        
        let task = Task { await runStartup(debugSettings: debugSettings) }
        startupTask = task
        return await task.value
    }
    
    // MARK: - Privacy Options
    
    /// Presents the privacy options form, then starts the SDK if the user's choice now allows ads.
    func presentPrivacyOptions() async -> Bool {
        do {
            try await consent.presentPrivacyOptions()
        } catch {
            log("Privacy options form failed - \(error.localizedDescription)")
        }
        return await startSDKIfAllowed()
    }
    
    /// Clears stored consent. Takes effect on the next app launch.
    func resetConsent() {
        consent.reset()
        isPrivacyOptionsRequired = consent.isPrivacyOptionsRequired
    }
    
    // MARK: - Private
    
    private func runStartup(debugSettings: ConsentDebugSettings?) async -> Bool {
        do {
            try await consent.requestUpdate(debugSettings: debugSettings)
        } catch {
            log("Consent info update failed - \(error.localizedDescription)")
        }
        
        await waitForWindow()
        
        do {
            try await consent.loadAndPresentIfRequired()
        } catch {
            log("Consent form failed - \(error.localizedDescription)")
        }
        
        return await startSDKIfAllowed()
    }
    
    private func startSDKIfAllowed() async -> Bool {
        isPrivacyOptionsRequired = consent.isPrivacyOptionsRequired
        guard consent.canRequestAds else {
            log("Ads cannot be requested until the user's consent allows it")
            return false
        }
        
        if let sdkStartTask = sdkStartTask {
            await sdkStartTask.value
        } else {
            let task = Task { await startSDK() }
            sdkStartTask = task
            await task.value
        }
        isSDKStarted = true
        return true
    }
    
    private func log(_ message: String) {
        #if DEBUG
        print("⚠️ AdmobKit: \(message)")
        #endif
    }
}
```

- [ ] **Step 8: 테스트 통과 확인** — test 명령. Expected: 모든 테스트 PASS.

- [ ] **Step 9: 빌드 2종 확인 후 커밋**

```bash
git add Package.swift Sources/AdmobKit/ConsentDebugGeography.swift Sources/AdmobKit/Internal/Consent Tests
git commit -m "feat: add UMP consent gateway and startup coordinator"
```

---

### Task 3: `AdmobKit` 연결과 `PrivacyOptionsButton`

**Files:**
- Create: `Sources/AdmobKit/Internal/Consent/KeyWindow.swift`
- Modify: `Sources/AdmobKit/AdmobKit.swift`
- Create: `Sources/AdmobKit/Views/Consent/PrivacyOptionsButton.swift`

**Interfaces:**
- Consumes: `AdsStartupCoordinator`, `UMPConsentGateway`, `ConsentDebugSettings` (Task 2)
- Produces: `AdmobKit: ObservableObject`; `@Published public private(set) var isInitialized: Bool`; `@Published public private(set) var isPrivacyOptionsRequired: Bool`; `public func initialize()`; `func waitUntilAdsCanBeRequested() async -> Bool` (internal); `public func presentPrivacyOptions() async`; `public func resetConsent()`; `public static func setConsentDebug(geography: ConsentDebugGeography, testDeviceIdentifiers: [String] = [])`
- Produces: `public struct PrivacyOptionsButton<Label: View>: View { public init(@ViewBuilder label: () -> Label) }`

- [ ] **Step 1: 창 대기** — `Sources/AdmobKit/Internal/Consent/KeyWindow.swift`:

```swift
//
//  KeyWindow.swift
//  AdmobKit
//
//  Waits for a key window, which the consent form presents from.
//

import UIKit

@MainActor
enum KeyWindow {
    
    /// Returns once the app has a key window, or after `timeout` seconds.
    static func wait(timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !exists, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private static var exists: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { scene in scene.windows.contains { $0.isKeyWindow } }
    }
}
```

- [ ] **Step 2: `AdmobKit.swift` 수정** — 다음을 반영한다(나머지 configure·accessor 코드는 그대로):
  - `import Combine` 추가, 선언을 `public final class AdmobKit: ObservableObject`로.
  - 문서 주석 Usage에 동의 흐름 한 줄 추가.
  - Configuration Storage에 `private static var consentDebugSettings: ConsentDebugSettings?`.
  - Properties:

```swift
    /// Indicates whether the Google Mobile Ads SDK has started and ads can be requested
    @Published public private(set) var isInitialized = false
    
    /// Whether this user must be offered a way to change their privacy choices
    /// (for example, users in the EEA). Show `PrivacyOptionsButton` in your settings screen.
    @Published public private(set) var isPrivacyOptionsRequired = false
    
    private let startup: AdsStartupCoordinator
```

  - Init:

```swift
    private init() {
        startup = AdsStartupCoordinator(
            consent: UMPConsentGateway(),
            startSDK: {
                let status = await MobileAds.shared.start()
                #if DEBUG
                AdmobKit.logInitializationStatus(status)
                #endif
            },
            waitForWindow: { await KeyWindow.wait() }
        )
    }
```

  - Consent Debugging (configure 뒤):

```swift
    // MARK: - Consent Debugging
    
    /// Simulates a region for the consent flow. Applied in Debug builds only; ignored in Release.
    ///
    /// Call before `initialize()`. Combine with `resetConsent()` to see the form again.
    ///
    /// - Parameters:
    ///   - geography: Region to simulate, e.g. `.eea` to see the GDPR form outside Europe
    ///   - testDeviceIdentifiers: Test device IDs the UMP SDK prints to the console on a real device
    public static func setConsentDebug(
        geography: ConsentDebugGeography,
        testDeviceIdentifiers: [String] = []
    ) {
        consentDebugSettings = ConsentDebugSettings(
            geography: geography,
            testDeviceIdentifiers: testDeviceIdentifiers
        )
    }
    
    private static var activeConsentDebugSettings: ConsentDebugSettings? {
        #if DEBUG
        return consentDebugSettings
        #else
        return nil
        #endif
    }
```

  - Initialization 섹션 교체:

```swift
    // MARK: - Initialization
    
    /// Gathers consent if required, then starts the Google Mobile Ads SDK.
    ///
    /// Call this method once at app launch, after calling `configure()`. Users in regions that
    /// require consent (EEA, UK, Switzerland) see the message configured in AdMob's
    /// Privacy & messaging. Ads are requested only after this flow allows it.
    public func initialize() {
        Task { _ = await waitUntilAdsCanBeRequested() }
    }
    
    /// Runs the startup flow if needed and returns whether ads can be requested.
    func waitUntilAdsCanBeRequested() async -> Bool {
        let canRequestAds = await startup.start(debugSettings: Self.activeConsentDebugSettings)
        syncState()
        return canRequestAds
    }
    
    // MARK: - Privacy Options
    
    /// Presents the privacy options form so the user can change their consent choices.
    public func presentPrivacyOptions() async {
        _ = await startup.presentPrivacyOptions()
        syncState()
    }
    
    /// Clears the stored consent so the form appears again on the next launch. Intended for testing.
    public func resetConsent() {
        startup.resetConsent()
        syncState()
    }
    
    private func syncState() {
        if isInitialized != startup.isSDKStarted {
            isInitialized = startup.isSDKStarted
        }
        if isPrivacyOptionsRequired != startup.isPrivacyOptionsRequired {
            isPrivacyOptionsRequired = startup.isPrivacyOptionsRequired
        }
    }
```

  - Debug Logging: `private func logInitializationStatus` → `private static func logInitializationStatus` (본문 동일).

- [ ] **Step 3: 버튼** — `Sources/AdmobKit/Views/Consent/PrivacyOptionsButton.swift`:

```swift
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
```

- [ ] **Step 4: 빌드 2종 + 테스트 확인** — 세 명령 모두 성공. Swift 6 strict에서 `@ObservedObject` 초기값이 격리 오류를 내면 `init`에서 `self._admobKit = ObservedObject(wrappedValue: AdmobKit.shared)`로 바꾼다.

- [ ] **Step 5: 커밋**

```bash
git add Sources/AdmobKit/AdmobKit.swift Sources/AdmobKit/Internal/Consent/KeyWindow.swift Sources/AdmobKit/Views/Consent
git commit -m "feat: gather UMP consent in initialize() and add PrivacyOptionsButton"
```

---

### Task 4: 전면 광고 안정화

**Files:**
- Create: `Sources/AdmobKit/Internal/AdFreshness.swift`
- Create: `Sources/AdmobKit/Views/Interstitial/DismissCallbacks.swift`
- Modify: `Sources/AdmobKit/Views/Interstitial/InterstitialAdLoader.swift`
- Create: `Tests/AdmobKitTests/AdFreshnessTests.swift`
- Create: `Tests/AdmobKitTests/DismissCallbacksTests.swift`

**Interfaces:**
- Consumes: `RetryBackoff` (Task 1), `AdmobKit.shared.waitUntilAdsCanBeRequested()` (Task 3)
- Produces: `enum AdFreshness { static let lifetime: TimeInterval; static func isExpired(loadedAt: Date, now: Date = Date()) -> Bool }`
- Produces: `struct DismissCallbacks { var isEmpty: Bool; mutating func append(_:); mutating func drain() -> [() -> Void] }`
- Produces: `public func showAd(from viewController: UIViewController? = nil, onDismiss: @escaping () -> Void)`

- [ ] **Step 1: 실패하는 테스트** — `Tests/AdmobKitTests/AdFreshnessTests.swift`:

```swift
import XCTest
@testable import AdmobKit

final class AdFreshnessTests: XCTestCase {
    
    private let loadedAt = Date(timeIntervalSinceReferenceDate: 0)
    
    func testAdIsFreshBeforeFiftyFiveMinutes() {
        XCTAssertFalse(AdFreshness.isExpired(loadedAt: loadedAt, now: loadedAt.addingTimeInterval(54 * 60)))
    }
    
    func testAdExpiresAtFiftyFiveMinutes() {
        XCTAssertTrue(AdFreshness.isExpired(loadedAt: loadedAt, now: loadedAt.addingTimeInterval(55 * 60)))
    }
    
    func testAdLeftInBackgroundForHoursIsExpired() {
        XCTAssertTrue(AdFreshness.isExpired(loadedAt: loadedAt, now: loadedAt.addingTimeInterval(3 * 60 * 60)))
    }
    
    func testClockMovedBackwardsCountsAsExpired() {
        XCTAssertTrue(AdFreshness.isExpired(loadedAt: loadedAt, now: loadedAt.addingTimeInterval(-60)))
    }
}
```

`Tests/AdmobKitTests/DismissCallbacksTests.swift`:

```swift
import XCTest
@testable import AdmobKit

final class DismissCallbacksTests: XCTestCase {
    
    func testDrainReturnsCallbacksInOrderAndEmpties() {
        var callbacks = DismissCallbacks()
        var calls: [Int] = []
        callbacks.append { calls.append(1) }
        callbacks.append { calls.append(2) }
        
        let drained = callbacks.drain()
        drained.forEach { $0() }
        
        XCTAssertTrue(callbacks.isEmpty)
        XCTAssertEqual(calls, [1, 2])
    }
    
    func testCallbackCanQueueAnotherWhileDrainedCallbacksRun() {
        var callbacks = DismissCallbacks()
        var calls: [Int] = []
        callbacks.append { calls.append(1) }
        
        // Simulates an onDismiss that calls showAd again while the ad is closing.
        for callback in callbacks.drain() {
            callback()
            callbacks.append { calls.append(2) }
        }
        callbacks.drain().forEach { $0() }
        
        XCTAssertEqual(calls, [1, 2])
        XCTAssertTrue(callbacks.isEmpty)
    }
}
```

- [ ] **Step 2: 실패 확인** — test 명령. Expected: `cannot find 'AdFreshness'`, `cannot find 'DismissCallbacks'`.

- [ ] **Step 3: 구현** — `Sources/AdmobKit/Internal/AdFreshness.swift`:

```swift
//
//  AdFreshness.swift
//  AdmobKit
//
//  Expiry rule for loaded full-screen ads.
//

import Foundation

/// Google: "ads expire after an hour". Refresh a little earlier to stay on the safe side.
enum AdFreshness {
    
    static let lifetime: TimeInterval = 55 * 60
    
    /// An ad is expired once `lifetime` has passed, or if the clock moved backwards since loading.
    static func isExpired(loadedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(loadedAt)
        return age < 0 || age >= lifetime
    }
}
```

`Sources/AdmobKit/Views/Interstitial/DismissCallbacks.swift`:

```swift
//
//  DismissCallbacks.swift
//  AdmobKit
//
//  Collects onDismiss callbacks requested while an interstitial is on screen.
//

import Foundation

struct DismissCallbacks {
    
    private var callbacks: [() -> Void] = []
    
    var isEmpty: Bool {
        callbacks.isEmpty
    }
    
    mutating func append(_ callback: @escaping () -> Void) {
        callbacks.append(callback)
    }
    
    /// Removes and returns all callbacks. Call them after this returns, so a callback can
    /// safely queue another one (for example, by calling `showAd` again).
    mutating func drain() -> [() -> Void] {
        defer { callbacks.removeAll() }
        return callbacks
    }
}
```

- [ ] **Step 4: 테스트 통과 확인** — test 명령. Expected: PASS.

- [ ] **Step 5: 로더 교체** — `InterstitialAdLoader` 클래스 본문을 다음으로 바꾼다(`InterstitialDelegateHandler`는 그대로):

```swift
@MainActor
public final class InterstitialAdLoader: NSObject {
    
    // MARK: - Properties
    
    private var interstitialAd: InterstitialAd?
    private var loadedAt: Date?
    private var delegateHandler: InterstitialDelegateHandler?
    private var dismissCallbacks = DismissCallbacks()
    private var isPresenting = false
    private var _isLoading = false
    private var retryBackoff = RetryBackoff()
    private var retryTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    
    // MARK: - Init
    
    public override init() {
        super.init()
    }
    
    // MARK: - Loading
    
    /// Preloads an interstitial. Waits for consent and SDK start-up, and retries failed
    /// loads 5 times with growing delays (5, 10, 20, 40, 60 seconds).
    public func loadAd() {
        retryBackoff.reset()
        startLoading()
    }
    
    private func startLoading() {
        guard !_isLoading, interstitialAd == nil else { return }
        
        retryTask?.cancel()
        retryTask = nil
        _isLoading = true
        
        Task { [weak self] in
            guard await AdmobKit.shared.waitUntilAdsCanBeRequested() else {
                self?._isLoading = false
                return
            }
            await self?.requestAd()
        }
    }
    
    private func requestAd() async {
        let adUnitID = AdmobKit.interstitialAdUnitID
        
        #if DEBUG
        print("🔄 AdmobKit: Interstitial loading... (adUnitID: \(adUnitID))")
        #endif
        
        do {
            let ad = try await InterstitialAd.load(with: adUnitID, request: Request())
            _isLoading = false
            retryBackoff.reset()
            
            #if DEBUG
            print("✅ AdmobKit: Interstitial loaded successfully")
            #endif
            
            interstitialAd = ad
            loadedAt = Date()
            delegateHandler = InterstitialDelegateHandler(loader: self)
            ad.fullScreenContentDelegate = delegateHandler
            scheduleExpiryRefresh()
        } catch {
            _isLoading = false
            
            #if DEBUG
            print("❌ AdmobKit: Interstitial failed - \(error.localizedDescription)")
            #endif
            
            scheduleRetry()
        }
    }
    
    private func scheduleRetry() {
        guard let delay = retryBackoff.nextDelay() else {
            #if DEBUG
            print("⏸️ AdmobKit: Interstitial retries exhausted until the next loadAd() or showAd()")
            #endif
            return
        }
        
        #if DEBUG
        print("⏳ AdmobKit: Retrying interstitial in \(Int(delay))s")
        #endif
        
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startLoading()
        }
    }
    
    // MARK: - Expiry
    
    private func scheduleExpiryRefresh() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AdFreshness.lifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refreshExpiredAd()
        }
    }
    
    private func refreshExpiredAd() {
        guard !isPresenting, interstitialAd != nil else { return }
        
        #if DEBUG
        print("⌛ AdmobKit: Interstitial expired, reloading")
        #endif
        
        clearAd()
        loadAd()
    }
    
    private func clearAd() {
        interstitialAd = nil
        loadedAt = nil
        delegateHandler = nil
        expiryTask?.cancel()
        expiryTask = nil
    }
    
    // MARK: - Presenting
    
    /// Presents the interstitial if one is ready.
    ///
    /// - Parameters:
    ///   - viewController: View controller to present from. `nil` uses the top view controller.
    ///   - onDismiss: Called after the ad closes, or immediately if no ad is ready.
    public func showAd(from viewController: UIViewController? = nil, onDismiss: @escaping () -> Void) {
        if isPresenting {
            dismissCallbacks.append(onDismiss)
            return
        }
        
        if let loadedAt = loadedAt, AdFreshness.isExpired(loadedAt: loadedAt) {
            #if DEBUG
            print("⌛ AdmobKit: Interstitial expired before showing")
            #endif
            clearAd()
        }
        
        guard let ad = interstitialAd else {
            #if DEBUG
            print("⚠️ AdmobKit: Interstitial not ready, skipping")
            #endif
            onDismiss()
            loadAd()
            return
        }
        
        #if DEBUG
        print("🎬 AdmobKit: Presenting interstitial")
        #endif
        
        isPresenting = true
        expiryTask?.cancel()
        expiryTask = nil
        dismissCallbacks.append(onDismiss)
        ad.present(from: viewController)
    }
    
    fileprivate func handleAdDismissed() {
        #if DEBUG
        print("👋 AdmobKit: Interstitial dismissed")
        #endif
        
        isPresenting = false
        clearAd()
        let callbacks = dismissCallbacks.drain()
        loadAd()
        callbacks.forEach { $0() }
    }
}
```

- [ ] **Step 6: 빌드 2종 + 테스트 확인** — 세 명령 모두 성공.

- [ ] **Step 7: 커밋**

```bash
git add Sources/AdmobKit/Internal/AdFreshness.swift Sources/AdmobKit/Views/Interstitial Tests
git commit -m "feat: retry failed interstitial loads, refresh expired ads, allow nil presenter"
```

---

### Task 5: 적응형 배너 (opt-in)

**Files:**
- Create: `Sources/AdmobKit/Internal/BannerRequestTracker.swift`
- Modify: `Sources/AdmobKit/Views/Banner/AdBannerView.swift`
- Create: `Tests/AdmobKitTests/BannerRequestTrackerTests.swift`

**Interfaces:**
- Consumes: `AdmobKit.shared.waitUntilAdsCanBeRequested()` (Task 3)
- Produces: `struct BannerRequestTracker { mutating func shouldRequest(forWidth width: CGFloat) -> Bool }`
- Produces: `public enum AdBannerSize: Sendable { case standard, adaptive }`, `public init(size: AdBannerSize = .standard)`

- [ ] **Step 1: 실패하는 테스트** — `Tests/AdmobKitTests/BannerRequestTrackerTests.swift`:

```swift
import XCTest
@testable import AdmobKit

final class BannerRequestTrackerTests: XCTestCase {
    
    func testIgnoresZeroWidthFromFirstLayoutPass() {
        var tracker = BannerRequestTracker()
        
        XCTAssertFalse(tracker.shouldRequest(forWidth: 0))
        XCTAssertTrue(tracker.shouldRequest(forWidth: 375))
    }
    
    func testRequestsOnlyWhenWidthChanges() {
        var tracker = BannerRequestTracker()
        
        XCTAssertTrue(tracker.shouldRequest(forWidth: 375))
        XCTAssertFalse(tracker.shouldRequest(forWidth: 375))
        XCTAssertTrue(tracker.shouldRequest(forWidth: 812))
        XCTAssertTrue(tracker.shouldRequest(forWidth: 375))
    }
}
```

- [ ] **Step 2: 실패 확인** — test 명령. Expected: `cannot find 'BannerRequestTracker'`.

- [ ] **Step 3: 구현** — `Sources/AdmobKit/Internal/BannerRequestTracker.swift`:

```swift
//
//  BannerRequestTracker.swift
//  AdmobKit
//
//  Decides when a banner needs a new ad request.
//

import CoreGraphics

/// A banner needs a request on its first usable width and whenever the width changes
/// (rotation, split view), as Google recommends for adaptive banners.
struct BannerRequestTracker {
    
    private var lastRequestedWidth: CGFloat?
    
    mutating func shouldRequest(forWidth width: CGFloat) -> Bool {
        guard width > 0, width != lastRequestedWidth else { return false }
        lastRequestedWidth = width
        return true
    }
}
```

- [ ] **Step 4: 테스트 통과 확인** — test 명령. Expected: PASS.

- [ ] **Step 5: 배너 뷰 수정** — `AdBannerView.swift`:

`AdBannerView` 위에 추가하고 문서 주석 Usage에 `AdBannerView(size: .adaptive)` 예시 추가:

```swift
/// Banner sizes supported by `AdBannerView`.
public enum AdBannerSize: Sendable {
    /// Fixed 320x50 banner, centered.
    case standard
    /// Large anchored adaptive banner: full available width, 50 to 150 points tall.
    case adaptive
}
```

`AdBannerView`:

```swift
public struct AdBannerView: View {
    
    @State private var adHeight: CGFloat = 0
    private let size: AdBannerSize
    
    public init(size: AdBannerSize = .standard) {
        self.size = size
    }
    
    public var body: some View {
        BannerViewRepresentable(size: size, adHeight: $adHeight)
            .frame(height: adHeight)
            .animation(.easeInOut(duration: 0.25), value: adHeight)
    }
}
```

`BannerViewRepresentable`:

```swift
private struct BannerViewRepresentable: UIViewRepresentable {
    
    let size: AdBannerSize
    @Binding var adHeight: CGFloat
    
    func makeUIView(context: Context) -> BannerContainerView {
        BannerContainerView(size: size, adHeight: $adHeight)
    }
    
    func updateUIView(_ uiView: BannerContainerView, context: Context) {}
}
```

`BannerContainerView` 본문(델리게이트 확장은 `bannerViewDidReceiveAd`만 바꾼다):

```swift
private class BannerContainerView: UIView {
    
    private let size: AdBannerSize
    private var bannerView: BannerView?
    private var adHeight: Binding<CGFloat>
    private var canRequestAds = false
    private var requestTracker = BannerRequestTracker()
    
    init(size: AdBannerSize, adHeight: Binding<CGFloat>) {
        self.size = size
        self.adHeight = adHeight
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        guard window != nil, bannerView == nil else { return }
        
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdmobKit.bannerAdUnitID
        banner.delegate = self
        banner.rootViewController = findViewController()
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        bannerView = banner
        
        Task { [weak self] in
            guard await AdmobKit.shared.waitUntilAdsCanBeRequested() else { return }
            self?.canRequestAds = true
            self?.loadIfNeeded()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        loadIfNeeded()
    }
    
    private func loadIfNeeded() {
        guard canRequestAds, let banner = bannerView else { return }
        
        let width = size == .standard ? AdSizeBanner.size.width : bounds.width
        guard requestTracker.shouldRequest(forWidth: width) else { return }
        
        if size == .adaptive {
            banner.adSize = largeAnchoredAdaptiveBanner(width: width)
        }
        banner.load(Request())
        
        #if DEBUG
        print("🔄 AdmobKit: Banner loading... (adUnitID: \(banner.adUnitID ?? "nil"), width: \(width))")
        #endif
    }
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let vc = nextResponder as? UIViewController {
                return vc
            }
            responder = nextResponder
        }
        return window?.rootViewController
    }
}
```

델리게이트:

```swift
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        #if DEBUG
        print("✅ AdmobKit: Banner loaded successfully (height: \(bannerView.adSize.size.height))")
        #endif
        
        let height = bannerView.adSize.size.height
        DispatchQueue.main.async {
            self.adHeight.wrappedValue = height
        }
    }
```

Preview에 `AdBannerView(size: .adaptive)` 하나 추가.

- [ ] **Step 6: 빌드 2종 + 테스트 확인** — 세 명령 모두 성공.

- [ ] **Step 7: 커밋**

```bash
git add Sources/AdmobKit/Internal/BannerRequestTracker.swift Sources/AdmobKit/Views/Banner Tests
git commit -m "feat: add opt-in large anchored adaptive banner and wait for consent before loading"
```

---

### Task 6: 시뮬레이터 실제 화면 검증 (커밋 없음)

**Files (scratchpad, 저장소 밖):**
- Create: `<scratchpad>/AdmobKitDemo.swiftpm/Package.swift`
- Create: `<scratchpad>/AdmobKitDemo.swiftpm/Info.plist`
- Create: `<scratchpad>/AdmobKitDemo.swiftpm/DemoApp.swift`

- [ ] **Step 1: 앱 패키지** — `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "AdmobKitDemo",
    platforms: [.iOS("16.0")],
    products: [
        .iOSApplication(
            name: "AdmobKitDemo",
            targets: ["AppModule"],
            bundleIdentifier: "com.kirade.admobkitdemo",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight],
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    dependencies: [
        .package(path: "<worktree 경로>")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [.product(name: "AdmobKit", package: "consent-banner-interstitial")],
            path: ".",
            exclude: ["Info.plist"]
        )
    ]
)
```

`Info.plist`: `GADApplicationIdentifier` = `ca-app-pub-3940256099942544~1458002511`(Google 샘플 앱 ID), `NSUserTrackingUsageDescription` = 테스트 문구.

`DemoApp.swift`: 실행 인자 `-geography eea|other`로 `AdmobKit.setConsentDebug`를 지정하고 `-reset`이면 `resetConsent()`를 부른 뒤 `configure()`/`initialize()`. 화면에는 `PrivacyOptionsButton`, `AdBannerView(size: .adaptive)`, 그리고 실행 인자 `-autoShowInterstitial`이면 광고가 준비된 뒤(15초 후) `showAd`를 자동 호출하는 코드.

- [ ] **Step 2: 빌드·실행** — `.swiftpm` 디렉터리에서 `xcodebuild build -scheme AdmobKitDemo -destination "$(bash <worktree>/scripts/simulator-destination.sh)" -derivedDataPath <scratch>`. 이어서 `xcrun simctl boot/install/launch`로 실행한다.

- [ ] **Step 3: 시나리오 확인 (스크린샷)**
  - `-geography eea -reset`: 동의 화면이 뜬다.
  - `-geography other -autoShowInterstitial`: 동의 화면 없이 적응형 배너가 보이고, 15초 뒤 전면 광고가 뜬다.
  - 각 시나리오의 콘솔 로그(`xcrun simctl launch --console-pty`)로 순서(동의 → SDK 시작 → 로드)를 확인한다.

- [ ] **Step 4: 빌드가 안 되는 경우** — 2~3번 시도해도 `.swiftpm` 앱이 빌드되지 않으면 중단하고, Task 7 README에 "실제 앱 확인 체크리스트"를 넣고 최종 보고에 명시한다.

---

### Task 7: 문서

**Files:**
- Modify: `README.md`, `AGENTS.md`, `.gitignore`

- [ ] **Step 1: `.gitignore`** — `# Swift Package Manager` 구획 위에 `# Claude Code worktrees` / `.claude/worktrees/` 추가.

- [ ] **Step 2: README** — 다음을 반영한다.
  - Features: "GDPR Consent (UMP)", "Adaptive Banners (opt-in)" 추가.
  - Setup 1에 이어 "2. Set up consent messages": AdMob 콘솔 Privacy & messaging에서 "European regulations" 메시지 생성·게시(없으면 아무에게도 안 뜸), IDFA 메시지를 켜면 `NSUserTrackingUsageDescription` 필수 경고.
  - Initialize 설명: `initialize()`가 동의 수집 후 SDK를 시작하고, 광고는 그 뒤 요청됨.
  - "Privacy options button" 절: `PrivacyOptionsButton { Text("Privacy Settings") }`를 설정 화면에 넣기.
  - "Testing consent" 절: `#if DEBUG` 안에서 `AdmobKit.setConsentDebug(geography: .eea)`, `AdmobKit.shared.resetConsent()`; 실기기에서는 콘솔에 찍힌 테스트 기기 ID를 `testDeviceIdentifiers`에 넣기(Task 6에서 시뮬레이터 자동 인식 여부를 확인해 반영).
  - 배너: `AdBannerView(size: .adaptive)` 예시와 높이 50~150pt·너비 변경 시 재요청 설명. Roadmap의 Adaptive Banner Sizes 체크.
  - 전면 광고: `showAd { }`(뷰 컨트롤러 생략) 예시로 교체, 재시도·55분 갱신·표시 중 중복 호출 설명.
  - Migrating 절에 "Upgrading to 2.1" 추가: 코드 변경 불필요, AdMob 메시지 생성과 `PrivacyOptionsButton` 추가 권장.
- [ ] **Step 3: AGENTS.md** — STRUCTURE(새 파일, Tests, scripts), CODE MAP(새 심볼 줄 번호는 최종 파일 기준으로 다시 뽑기), CONVENTIONS(광고 로드 전 `waitUntilAdsCanBeRequested()` 필수), COMMANDS(test 명령), NOTES("No tests" 삭제, 동의 흐름 요약).
- [ ] **Step 4: 커밋**

```bash
git add README.md AGENTS.md .gitignore
git commit -m "docs: document consent, adaptive banners, and interstitial changes"
```

---

### Task 8: 리뷰, PR, 릴리스

- [ ] **Step 1: 전체 브랜치 리뷰** — 새 리뷰어(가장 강한 모델)에게 spec과 이 계획 대비 브랜치 diff 리뷰를 맡기고, 확인된 문제를 고친다.
- [ ] **Step 2: PR** — 브랜치 push, PR 생성(본문: 요약, 사용자 할 일 2가지, 테스트 결과). CI(빌드 2종 + 테스트) 통과 확인.
- [ ] **Step 3: 병합·태그** — `gh pr merge --merge --delete-branch`, main 갱신, `git tag -a v2.1.0`, `git push origin v2.1.0`.
- [ ] **Step 4: 확인** — Release 워크플로 성공, `gh release view v2.1.0`, scratch 소비자 패키지로 `from: "2.0.0"`이 2.1.0을 받아 빌드되는지 확인.

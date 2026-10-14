# AdmobKit 2.1.0 설계: UMP 동의, 적응형 배너, 전면 광고 안정화

- 작성일: 2026-10-15
- 상태: 승인됨 (대화에서 섹션 1~3 승인, "쭉 진행" 지시)
- 대상 버전: 2.1.0 (공개 API는 추가만, 변경·삭제 없음)

## 1. 배경과 목표

AdmobKit 2.0.0(GMA SDK 13) 이후 남은 후속 과제를 정리했다.

| 과제 | 결정 | 이유 |
|---|---|---|
| UMP 동의 | **진행** | 앱을 유럽(EEA)·영국·스위스 포함 전 세계에 배포한다. Google 인증 CMP가 없으면 해당 지역은 Limited Ads만 송출된다. |
| 적응형 배너 | **진행 (opt-in)** | 수익 개선. 다만 높이가 50~150pt로 바뀌어 레이아웃에 영향을 주므로 기본값은 유지한다. |
| 전면 광고 안정화 | **진행** | 로드 실패 후 재시도가 없고, 1시간 만료 처리가 없다. |
| AppTransaction 환경 감지 | 보류 | 기존 방식이 동작하고 경고도 안 뜬다. 대체 API는 iOS 16+, async 전용이라 위험이 더 크다. |
| 미사용 `rewardedAdUnitID` | 보류 | 삭제하면 공개 API가 깨진다. 보상형 광고가 필요해질 때 구현한다. |

성공 기준:
- 앱 코드를 바꾸지 않고 2.1.0으로 올리기만 하면, 유럽 사용자에게 동의 화면이 뜨고 동의 절차 뒤에만 광고를 요청한다.
- 한국 등 비규제 지역 사용자에게는 화면 변화가 없다.
- 기존 공개 API는 소스 호환을 유지한다.

## 2. 접근 방식

**중앙 대기 지점(채택).** `AdmobKit`이 "광고 요청 가능" 상태를 하나의 비동기 작업으로 관리하고, 배너와 전면 광고는 로드 직전에 이 작업을 `await`한다. 앱이 `initialize()`를 빠뜨려도 첫 광고 요청 때 자동으로 시작한다.

검토 후 제외한 방식:
- 알림(Notification) 구독: 준비가 끝난 뒤 생긴 뷰가 알림을 놓치는 경쟁 조건이 생긴다.
- SDK 시작만 막고 광고 요청은 바로 하기: Google 지침("canRequestAds 확인 후 요청")에 어긋난다.

## 3. 공개 API (모두 추가)

```swift
// 기존 그대로 — initialize()가 동의 절차까지 처리
AdmobKit.configure(bannerAdUnitID:interstitialAdUnitID:rewardedAdUnitID:)
AdmobKit.shared.initialize()
AdmobKit.shared.isInitialized              // @Published. SDK 시작이 끝나 광고를 요청할 수 있음

// 개인정보 설정 진입점
AdmobKit.shared.isPrivacyOptionsRequired   // @Published. 규제 지역 사용자에게만 true
AdmobKit.shared.presentPrivacyOptions() async
PrivacyOptionsButton { Text("개인정보 설정") }   // 필요할 때만 보이는 SwiftUI 버튼

// 동의 흐름 시험 (setConsentDebug는 Debug 빌드에서만 적용, Release에서는 무시)
AdmobKit.setConsentDebug(geography: ConsentDebugGeography, testDeviceIdentifiers: [String])
AdmobKit.shared.resetConsent()

// 배너
public enum AdBannerSize { case standard, adaptive }
AdBannerView(size: AdBannerSize = .standard)

// 전면 광고
interstitial.showAd(from: UIViewController? = nil, onDismiss: @escaping () -> Void)
```

- `AdmobKit`은 `ObservableObject`가 된다. iOS 15 지원 때문에 `@Observable`은 쓰지 않는다.
- UMP 타입은 공개 API에 드러내지 않는다. `ConsentDebugGeography`(`.eea`, `.regulatedUSState`, `.other`)는 AdmobKit 자체 enum이다.
- `Package.swift`에 `swift-package-manager-google-user-messaging-platform`(`from: "3.0.0"`, 제품 `GoogleUserMessagingPlatform`)을 직접 의존성으로 추가한다. GMA 13은 UMP `1.1.0..<4.0.0`을 허용하므로 충돌하지 않는다.

## 4. 내부 구조

| 단위 | 위치 | 역할 |
|---|---|---|
| `ConsentGateway` (protocol) | `Internal/Consent/ConsentGateway.swift` | 동의 정보 갱신, 필요 시 동의 화면, 개인정보 설정 화면, `canRequestAds`, `isPrivacyOptionsRequired`, `reset()` |
| `UMPConsentGateway` | 같은 파일 | `ConsentGateway`의 실제 UMP 구현 |
| `AdsStartupCoordinator` | `Internal/Consent/AdsStartupCoordinator.swift` | 동의 → SDK 시작 흐름과 "광고 요청 가능" 작업을 소유. 동의 게이트웨이, SDK 시작 함수, 창 대기 함수를 주입받아 테스트할 수 있다 |
| `RetryBackoff` | `Internal/RetryBackoff.swift` | 재시도 간격 계산 (순수 값 타입) |
| `AdFreshness` | `Internal/AdFreshness.swift` | 로드 시각 기준 만료 판단 (순수 함수) |
| `DismissCallbacks` | `Views/Interstitial/DismissCallbacks.swift` | 표시 중 중복 호출된 `onDismiss` 모으기 (순수 값 타입) |

`AdmobKit`은 `AdsStartupCoordinator`를 하나 갖고, 그 결과를 `@Published` 속성으로 옮긴다. 배너와 전면 광고는 내부 API `AdmobKit.shared.waitUntilAdsCanBeRequested() async -> Bool`만 의존한다.

## 5. 동작

### 5.1 동의와 초기화

```
initialize() ─▶ 동의 정보 갱신 ─▶ 창 대기 ─▶ 필요하면 동의 화면 ─▶ canRequestAds?
                                                                 ├ true  ─▶ SDK 시작 ─▶ 광고 요청 가능
                                                                 └ false ─▶ 이번 세션은 광고 요청 안 함
```

- 진행 중인 작업 하나를 공유한다. `initialize()`나 대기 API가 여러 번 불려도 동의 절차와 SDK 시작은 한 번만 실행된다.
- 창 대기: 동의 화면은 창이 있어야 뜬다. 키 윈도우가 생길 때까지 100ms 간격으로 최대 3초 기다린 뒤 진행한다.
- 동의 정보 갱신이나 동의 화면 표시가 실패해도 멈추지 않는다. Google 지침대로 이전 세션의 동의 상태로 `canRequestAds`를 판단한다. 오류는 DEBUG에서만 출력한다.
- `canRequestAds`가 false면 그 세션 동안 결과(false)를 유지한다. 배너는 접힌 채로 있고, 전면 광고 `showAd`는 즉시 `onDismiss`를 호출한다. 다음 실행 때 다시 시도한다.
- 흐름이 끝나면 `isPrivacyOptionsRequired`를 갱신한다.
- `presentPrivacyOptions()`: 개인정보 설정 화면을 띄운 뒤 상태를 갱신한다. 그 결과 처음으로 `canRequestAds`가 true가 되면 SDK를 시작하고 `isInitialized`를 true로 바꾼다.
- `setConsentDebug`로 지정한 지역·테스트 기기는 DEBUG 빌드에서만 동의 정보 갱신 요청에 실린다.
- AdMob 콘솔에서 IDFA 안내 메시지를 켜면 앱 Info.plist에 `NSUserTrackingUsageDescription`이 필요하다. README에 경고한다.

### 5.2 배너

- 창에 붙으면 `BannerView`를 만들고, `waitUntilAdsCanBeRequested()`가 true를 돌려준 뒤 로드한다.
- `.standard`: `AdSizeBanner`(320x50), 가운데 정렬. 기존 동작과 같다.
- `.adaptive`: 컨테이너 너비로 `largeAnchoredAdaptiveBanner(width:)`를 계산한다. `layoutSubviews`에서 너비가 0보다 크고 마지막 요청 너비와 다르면 새로 요청한다(회전·분할 화면 대응).
- 광고 수신 시 높이를 `bannerView.adSize.size.height`로 바꾸고, 실패 시 0으로 접는다.

### 5.3 전면 광고

- `loadAd()`: 로드 중이거나 이미 광고가 있으면 무시한다. `waitUntilAdsCanBeRequested()`가 false면 로드하지 않는다.
- 로드 실패 시 `RetryBackoff`로 5→10→20→40→60초 간격으로 최대 5번 다시 시도한다. 성공하면 횟수를 초기화한다. 다 실패하면 멈추고, 다음 `loadAd()`나 준비되지 않은 상태에서의 `showAd()` 때 처음부터 다시 시작한다.
- 만료: 로드 시각을 기록한다. 로드 후 55분이 지나면 새로 받도록 예약한다(최선 노력). 앱이 백그라운드에 있으면 예약이 늦어질 수 있으므로 `showAd()` 시점에도 `AdFreshness`로 다시 확인한다. 만료된 광고는 버리고, 준비되지 않은 것으로 처리한 뒤 새로 받는다.
- `showAd(from: nil)`: 뷰 컨트롤러를 생략하면 SDK가 최상위 화면에서 띄운다. 광고가 없으면 `onDismiss`를 즉시 호출하고 로드를 시작한다.
- 광고가 떠 있는 동안 `showAd`가 또 불리면 콜백을 `DismissCallbacks`에 모았다가, 닫힐 때 모두 호출한다.
- 재시도·만료 예약 작업은 `[weak self]`로 잡아서 로더가 해제되면 아무것도 하지 않는다.

## 6. 테스트와 검증

### 6.1 자동 테스트 (`Tests/AdmobKitTests`, XCTest)

- `RetryBackoff`: 간격 순서, 최대 횟수 뒤 `nil`, `reset()` 후 처음부터.
- `AdFreshness`: 55분 미만은 유효, 이상은 만료.
- `DismissCallbacks`: 여러 콜백을 모았다가 한 번에 호출하고 비운다.
- `AdsStartupCoordinator` (가짜 `ConsentGateway` 주입):
  - 여러 번 불러도 SDK 시작은 한 번
  - `canRequestAds` false면 SDK를 시작하지 않고 false 반환
  - 동의 정보 갱신이 실패해도 이전 상태(`canRequestAds`)로 진행
  - 동의 화면 표시가 실패해도 진행
  - 개인정보 설정 후 처음 `canRequestAds`가 true가 되면 SDK 시작
  - `isPrivacyOptionsRequired` 반영

### 6.2 CI

- 기존 빌드 단계(Swift 5 모드, Swift 6 strict)에 `xcodebuild test`를 추가한다.
- 시뮬레이터는 기기 이름을 하드코딩하지 않고, 설치된 iPhone 시뮬레이터 중 하나의 UDID를 골라 `-destination id=<UDID>`로 지정한다.

### 6.3 실제 화면 검증

- 시뮬레이터용 최소 테스트 앱(Swift 패키지 형식 앱)을 만들어 Google 샘플 앱 ID와 `setConsentDebug(geography: .eea)`로 "동의 화면 → 적응형 배너 → 전면 광고"를 확인한다.
- 이 방식이 빌드되지 않으면 실제 앱에서 확인할 체크리스트로 대신하고, 그 사실을 보고한다.

## 7. 문서와 릴리스

- README: 동의 설정(AdMob 콘솔에서 유럽 규정 메시지 만들기), `NSUserTrackingUsageDescription` 경고, Debug 시험 방법, `PrivacyOptionsButton`, 적응형 배너, 바뀐 전면 광고 사용법.
- AGENTS.md: 새 구조와 규칙 반영. `.gitignore`에 `.claude/worktrees/` 추가.
- 워크트리 브랜치 → PR → CI 통과 → 병합 → `v2.1.0` 태그 → 릴리스 확인.

## 8. 릴리스 후 사용자 할 일

1. 앱마다 AdMob 콘솔 **개인정보 보호 및 메시지**에서 "유럽 규정" 메시지를 만들고 게시한다. 이게 없으면 코드가 있어도 동의 화면이 뜨지 않는다.
2. 앱 설정 화면에 `PrivacyOptionsButton`을 넣는다.

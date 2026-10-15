import UIKit
import GoogleMobileAds
@testable import AdmobKit

/// A loaded interstitial that records what the loader does with it.
@MainActor
final class FakeAd: NSObject, PresentableAd, FullScreenPresentingAd {
    
    weak var fullScreenContentDelegate: FullScreenContentDelegate?
    var presentError: Error?
    private(set) var presentCount = 0
    
    func canPresent(from viewController: UIViewController?) throws {
        if let presentError = presentError { throw presentError }
    }
    
    func present(from viewController: UIViewController?) {
        presentCount += 1
    }
    
    /// Simulates the user closing the ad.
    func dismiss() {
        fullScreenContentDelegate?.adDidDismissFullScreenContent?(self)
    }
}

/// Hands out queued load results; loads fail once the queue is empty.
@MainActor
final class FakeAdSource {
    
    var results: [Result<FakeAd, Error>] = []
    private(set) var loadCount = 0
    
    func load(_ adUnitID: String) async throws -> PresentableAd {
        loadCount += 1
        guard !results.isEmpty else { throw TestError() }
        return try results.removeFirst().get()
    }
}

/// Parks every sleep until a test wakes it, so pending retries can be observed.
@MainActor
final class FakeSleeper {
    
    private var pending: [(delay: TimeInterval, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var requestedDelays: [TimeInterval] = []
    private(set) var cancelledCount = 0
    
    func sleep(_ delay: TimeInterval) async {
        requestedDelays.append(delay)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append((delay, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancelledCount += 1 }
        }
    }
    
    /// Wakes the oldest sleep that asked for `delay`.
    func wake(delay: TimeInterval) {
        guard let index = pending.firstIndex(where: { $0.delay == delay }) else { return }
        pending.remove(at: index).continuation.resume()
    }
    
    var retryDelays: [TimeInterval] {
        requestedDelays.filter { $0 != AdFreshness.lifetime }
    }
}

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSinceReferenceDate: 0)
}

/// Lets main-actor tasks started by the code under test run to their next suspension.
@MainActor
func settle() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}

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

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

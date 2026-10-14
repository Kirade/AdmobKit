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

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
        // Simulates an onDismiss that calls showAd again while the ad is closing.
        callbacks.append {
            calls.append(1)
            callbacks.append { calls.append(2) }
        }
        
        callbacks.drain().forEach { $0() }
        callbacks.drain().forEach { $0() }
        
        XCTAssertEqual(calls, [1, 2])
        XCTAssertTrue(callbacks.isEmpty)
    }
}

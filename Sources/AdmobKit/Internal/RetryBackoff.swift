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

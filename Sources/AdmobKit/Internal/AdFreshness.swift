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

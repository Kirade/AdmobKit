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

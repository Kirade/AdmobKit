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

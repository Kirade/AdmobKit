//
//  KeyWindow.swift
//  AdmobKit
//
//  Waits for a key window, which the consent form presents from.
//

import UIKit

@MainActor
enum KeyWindow {
    
    /// Returns once the app has a key window, or after `timeout` seconds.
    static func wait(timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !exists, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private static var exists: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { scene in scene.windows.contains { $0.isKeyWindow } }
    }
}

//
//  PresentableAd.swift
//  AdmobKit
//
//  The parts of a loaded full-screen ad that InterstitialAdLoader uses.
//

import UIKit
import GoogleMobileAds

/// Lets `InterstitialAdLoader` work with `InterstitialAd` and with test doubles.
@MainActor
protocol PresentableAd: AnyObject {
    var fullScreenContentDelegate: FullScreenContentDelegate? { get set }
    func canPresent(from viewController: UIViewController?) throws
    func present(from viewController: UIViewController?)
}

extension InterstitialAd: PresentableAd {}

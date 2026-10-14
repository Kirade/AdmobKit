//
//  AdBannerView.swift
//  AdmobKit
//
//  SwiftUI banner ad view with automatic sizing.
//

import SwiftUI
import GoogleMobileAds

/// Banner sizes supported by `AdBannerView`.
public enum AdBannerSize: Sendable {
    /// Fixed 320x50 banner, centered.
    case standard
    /// Large anchored adaptive banner: full available width, 50 to 150 points tall.
    case adaptive
}

/// A SwiftUI view that displays an AdMob banner ad.
///
/// The banner automatically:
/// - Loads the appropriate ad unit ID based on environment
/// - Waits for consent and SDK start-up before requesting an ad
/// - Animates in when the ad loads successfully
/// - Hides when the ad fails to load
///
/// Usage:
/// ```swift
/// VStack {
///     // Your content
///     Spacer()
///     AdBannerView()                   // 320x50
///     // AdBannerView(size: .adaptive) // full width, 50-150pt tall
/// }
/// ```
public struct AdBannerView: View {

    @State private var adHeight: CGFloat = 0
    private let size: AdBannerSize

    public init(size: AdBannerSize = .standard) {
        self.size = size
    }

    public var body: some View {
        BannerViewRepresentable(size: size, adHeight: $adHeight)
            .frame(height: adHeight)
            .animation(.easeInOut(duration: 0.25), value: adHeight)
    }
}

// MARK: - UIViewRepresentable

private struct BannerViewRepresentable: UIViewRepresentable {

    let size: AdBannerSize
    @Binding var adHeight: CGFloat

    func makeUIView(context: Context) -> BannerContainerView {
        BannerContainerView(size: size, adHeight: $adHeight)
    }

    func updateUIView(_ uiView: BannerContainerView, context: Context) {}
}

// MARK: - Banner Container

private class BannerContainerView: UIView {

    private let size: AdBannerSize
    private var bannerView: BannerView?
    private var adHeight: Binding<CGFloat>
    private var canRequestAds = false
    private var requestTracker = BannerRequestTracker()

    init(size: AdBannerSize, adHeight: Binding<CGFloat>) {
        self.size = size
        self.adHeight = adHeight
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil, bannerView == nil else { return }

        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdmobKit.bannerAdUnitID
        banner.delegate = self
        banner.rootViewController = findViewController()
        banner.translatesAutoresizingMaskIntoConstraints = false

        addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        bannerView = banner

        Task { [weak self] in
            guard await AdmobKit.shared.waitUntilAdsCanBeRequested() else { return }
            self?.canRequestAds = true
            self?.loadIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard canRequestAds, let banner = bannerView else { return }

        let width = size == .standard ? AdSizeBanner.size.width : bounds.width
        guard requestTracker.shouldRequest(forWidth: width) else { return }

        if size == .adaptive {
            banner.adSize = largeAnchoredAdaptiveBanner(width: width)
        }
        banner.load(Request())

        #if DEBUG
        print("🔄 AdmobKit: Banner loading... (adUnitID: \(banner.adUnitID ?? "nil"), width: \(width))")
        #endif
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let vc = nextResponder as? UIViewController {
                return vc
            }
            responder = nextResponder
        }
        return window?.rootViewController
    }
}

// MARK: - BannerViewDelegate

extension BannerContainerView: BannerViewDelegate {

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        #if DEBUG
        print("✅ AdmobKit: Banner loaded successfully (height: \(bannerView.adSize.size.height))")
        #endif

        let height = bannerView.adSize.size.height
        DispatchQueue.main.async {
            self.adHeight.wrappedValue = height
        }
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        #if DEBUG
        print("❌ AdmobKit: Banner failed - \(error.localizedDescription)")
        #endif

        DispatchQueue.main.async {
            self.adHeight.wrappedValue = 0
        }
    }

    func bannerViewDidRecordImpression(_ bannerView: BannerView) {
        #if DEBUG
        print("📊 AdmobKit: Banner impression recorded")
        #endif
    }

    func bannerViewDidRecordClick(_ bannerView: BannerView) {
        #if DEBUG
        print("👆 AdmobKit: Banner clicked")
        #endif
    }
}

#if DEBUG
struct AdBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            Text("Content above banner")
            Spacer()
            AdBannerView()
            AdBannerView(size: .adaptive)
        }
    }
}
#endif

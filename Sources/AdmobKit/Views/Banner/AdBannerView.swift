//
//  AdBannerView.swift
//  AdmobKit
//
//  SwiftUI banner ad view with automatic sizing.
//

import SwiftUI
import GoogleMobileAds

/// A SwiftUI view that displays an AdMob banner ad.
///
/// The banner automatically:
/// - Loads the appropriate ad unit ID based on environment
/// - Animates in when the ad loads successfully
/// - Hides when the ad fails to load
///
/// Usage:
/// ```swift
/// VStack {
///     // Your content
///     Spacer()
///     AdBannerView()
/// }
/// ```
public struct AdBannerView: View {
    
    @State private var adHeight: CGFloat = 0
    
    public init() {}
    
    public var body: some View {
        BannerViewRepresentable(adHeight: $adHeight)
            .frame(height: adHeight)
            .animation(.easeInOut(duration: 0.25), value: adHeight)
    }
}

// MARK: - UIViewRepresentable

private struct BannerViewRepresentable: UIViewRepresentable {
    
    @Binding var adHeight: CGFloat
    
    func makeUIView(context: Context) -> BannerContainerView {
        let container = BannerContainerView(adHeight: $adHeight)
        return container
    }
    
    func updateUIView(_ uiView: BannerContainerView, context: Context) {}
}

// MARK: - Banner Container

private class BannerContainerView: UIView {
    
    private var bannerView: BannerView?
    private var adHeight: Binding<CGFloat>
    private let standardBannerHeight: CGFloat = 50
    
    init(adHeight: Binding<CGFloat>) {
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
        
        banner.load(Request())
        bannerView = banner
        
        #if DEBUG
        print("🔄 AdmobKit: Banner loading... (adUnitID: \(banner.adUnitID ?? "nil"))")
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
        print("✅ AdmobKit: Banner loaded successfully")
        #endif
        
        DispatchQueue.main.async {
            self.adHeight.wrappedValue = self.standardBannerHeight
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
        }
    }
}
#endif

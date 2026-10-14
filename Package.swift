// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AdmobKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AdmobKit",
            targets: ["AdmobKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.0.0"
        )
    ],
    targets: [
        .target(
            name: "AdmobKit",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads")
            ]
        ),
        .testTarget(
            name: "AdmobKitTests",
            dependencies: ["AdmobKit"]
        ),
    ]
)

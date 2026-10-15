// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "AdmobKitDemo",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "AdmobKitDemo",
            targets: ["AppModule"],
            bundleIdentifier: "com.kirade.admobkitdemo",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight],
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    dependencies: [
        // The AdmobKit checkout this example lives in. `name:` keeps the package reference
        // stable when the checkout directory has another name (e.g. a worktree).
        .package(name: "AdmobKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "AdmobKit", package: "AdmobKit")
            ],
            path: ".",
            exclude: ["Info.plist", "README.md"]
        )
    ]
)

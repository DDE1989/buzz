// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BuzzPushKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BuzzPushKit", targets: ["BuzzPushKit"])
    ],
    dependencies: [
        // Fork of 0.21.1 with a one-line fix for Xcode 27's Swift ("Ambiguous use of
        // 'words'"). Newer upstream releases need a SwiftPM build plugin that Xcode 27
        // cannot yet resolve for the notification extension.
        .package(url: "https://github.com/DDE1989/swift-secp256k1.git", exact: "0.21.1-xcode27")
    ],
    targets: [
        .target(
            name: "BuzzPushKit",
            dependencies: [.product(name: "P256K", package: "swift-secp256k1")]
        ),
        .testTarget(
            name: "BuzzPushKitTests",
            dependencies: [
                "BuzzPushKit",
                .product(name: "P256K", package: "swift-secp256k1"),
            ],
            resources: [.copy("Fixtures/app_attest_transcripts.json")]
        ),
    ]
)

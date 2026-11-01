// swift-tools-version:5.9
// PoliceHQCore — offline legal-reference core for the Police HQ iPhone app.
// No third-party dependencies: SQLite3, CryptoKit, CommonCrypto and Foundation are
// system frameworks, so nothing is downloaded at build time or used at runtime
// over the network.
import PackageDescription

let package = Package(
    name: "PoliceHQCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoliceHQCore", targets: ["PoliceHQCore"])
    ],
    targets: [
        .target(
            name: "PoliceHQCore",
            resources: [.copy("Resources/content_schema.sql")]
        ),
        .testTarget(
            name: "PoliceHQCoreTests",
            dependencies: ["PoliceHQCore"]
        )
    ]
)

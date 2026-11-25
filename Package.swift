// swift-tools-version: 6.4
import PackageDescription

// The compiler settings every target of this package shares.
// A target passes swiftSettings: sharedSwiftSettings, or appends its own settings to it.
let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "swift-onepassword",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OnePassword", targets: ["OnePassword"])
    ],
    targets: [
        // The Go SDK, built from core/ as a static library.
        // The tag in the url is core- and the first 12 hex digits of a hash over the files the build reads.
        // `mise run xcframework:pin` rewrites the url and the checksum after the XCFramework workflow publishes the release.
        .binaryTarget(
            name: "COnePassword",
            url: "https://github.com/victor-software-house/swift-onepassword/releases/download/core-3020071e16dc/COnePassword.xcframework.zip",
            checksum: "2818c3c684034ec4e800727114bae7371060725698e7c7539804547602dc460f"
        ),
        .target(
            name: "OnePassword",
            dependencies: ["COnePassword"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "OnePasswordTests",
            dependencies: ["OnePassword"],
            resources: [.copy("Fixtures")],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)

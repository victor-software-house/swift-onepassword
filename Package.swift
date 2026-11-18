// swift-tools-version: 6.4
import PackageDescription

let strict: [SwiftSetting] = [
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
        .library(name: "OnePassword", targets: ["OnePassword"]),
    ],
    targets: [
        // The Go SDK, built from core/ as a static library.
        // The tag in the url is core- and the first 12 hex digits of the git tree hash of core/.
        // `mise run core:pin` rewrites the url and the checksum after the Core workflow publishes the release.
        .binaryTarget(
            name: "COnePassword",
            url: "https://github.com/victor-software-house/swift-onepassword/releases/download/core-3ed96212cde2/COnePassword.xcframework.zip",
            checksum: "7f1e9d1a7ef9c1c0b1f481597e916341df21436882c859c2b9ee627c98fcebc4"
        ),
        .target(
            name: "OnePassword",
            dependencies: ["COnePassword"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "OnePasswordTests",
            dependencies: ["OnePassword"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)

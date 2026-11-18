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
            url: "https://github.com/victor-software-house/swift-onepassword/releases/download/core-e824066e03c2/COnePassword.xcframework.zip",
            checksum: "77dcaf9d386120225f81e04aa79ac21e6fada71fd28bf129b39daa5b34ab7250"
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

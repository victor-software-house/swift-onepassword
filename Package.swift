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
            url: "https://github.com/victor-software-house/swift-onepassword/releases/download/core-85a6a8be3369/COnePassword.xcframework.zip",
            checksum: "f7c1390294e11c322cdd102f462a1f4dc610426fd50957e63e55b2564326cd22"
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

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
        // The Go SDK, built from core/ as a static library. The tag in the url is core- and the
        // first 12 hex digits of the git tree hash of core/; `mise run core:pin` rewrites the
        // url and the checksum after the Core workflow publishes the release.
        .binaryTarget(
            name: "COnePassword",
            url: "https://github.com/victor-software-house/swift-onepassword/releases/download/core-b1552b06f493/COnePassword.xcframework.zip",
            checksum: "2730eefb89d9608c692d916f7aaac6ba4d518004709549dd8c851add6fc1e2df"
        ),
        .target(
            name: "OnePassword",
            dependencies: ["COnePassword"],
            swiftSettings: strict,
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedLibrary("resolv"),
            ]
        ),
        .testTarget(
            name: "OnePasswordTests",
            dependencies: ["OnePassword"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)

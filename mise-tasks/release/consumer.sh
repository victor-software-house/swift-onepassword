#!/bin/sh
#MISE description="Build a throwaway package that depends on a released version and links its binary; macOS only"
# The first argument is the version.
# The package does what an app does.
# It depends on the repository's URL at that exact version and links the OnePassword module.
# The check passes when the client starts and a malformed token gets the authenticationFailed code
# from 1Password's core.
set -eu
version=${1:?usage: release:consumer <version>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/consumer"
cat > "$work/Package.swift" << PACKAGE
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "consumer",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/victor-software-house/swift-onepassword.git", exact: "$version"),
    ],
    targets: [
        .executableTarget(
            name: "consumer",
            dependencies: [.product(name: "OnePassword", package: "swift-onepassword")]
        ),
    ]
)
PACKAGE
cat > "$work/Sources/consumer/main.swift" << 'MAIN'
import Foundation
import OnePassword

do throws(OnePasswordError) {
    _ = try await Client(token: "malformed-token", integrationName: "consumer-check", integrationVersion: "0")
    print("a malformed token started a client")
    exit(1)
} catch {
    guard error.code == .authenticationFailed else {
        print("a malformed token gave \(error.code), not authenticationFailed")
        exit(1)
    }
    print("linked: \(error)")
}
MAIN
cd "$work"
swift run consumer

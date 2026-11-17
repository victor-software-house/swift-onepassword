#!/bin/sh
#MISE description="Build a throwaway package that depends on a released version and links its binary; macOS only"
# The version is the first argument. The package is what an app does: it names the repository's
# URL and an exact version, and links the OnePassword module. The check passes when the client
# starts and a malformed token gets the authentication kind from 1Password's core.
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
    guard error.kind == .authentication else {
        print("a malformed token gave \(error.kind), not authentication")
        exit(1)
    }
    print("linked: \(error)")
}
MAIN
cd "$work"
swift run consumer

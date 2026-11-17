# swift-onepassword

A Swift binding of [1Password's Go SDK](https://github.com/1password/onepassword-sdk-go) for macOS.  
It reads vaults and items with a service account token, with no 1Password CLI and no helper process.

The Go SDK is built as a static library and shipped as an XCFramework, so an app that uses this package stays one binary.

## Use

Add the package at an exact version:

```swift
.package(url: "https://github.com/victor-software-house/swift-onepassword.git", exact: "<version>")
```

Then depend on the `OnePassword` product.  
The module needs macOS 26 or later.

```swift
import Foundation
import OnePassword

// The token comes from stdin, never from arguments or the environment.
guard let token = readLine(strippingNewline: true) else { exit(1) }

do throws(OnePasswordError) {
    let client = try await Client(token: token, integrationName: "my-tool", integrationVersion: "1.0")

    for vault in try await client.vaults() {
        for overview in try await client.items(vaultID: vault.id) where overview.category == "SshKey" {
            let item = try await client.item(vaultID: vault.id, itemID: overview.id)
            print(item.title, item.fields.map(\.title))
        }
    }
} catch {
    // `error.kind` is `.authentication`, `.rateLimited` or `.other`; the message never holds the token.
    print(error)
}
```

| Call | Costs against 1Password's limits |
|:--|:--|
| `vaults()` | 1 read, and each vault's `contentVersion` rises when its contents change |
| `items(vaultID:)` | 1 read |
| `item(vaultID:itemID:)` | 2 reads |

A `Client` holds one 1Password client until it is freed.  
Its first creation loads 1Password's core, which takes about a second.  
Keep the client and reuse it.

## The binary

1. `core/` is a Go module of one file, `shim.go`.  
   It calls the SDK, pinned to an exact version in `core/go.mod`, and exports four C functions: `op_client_open`, `op_call`, `op_client_close` and `op_free`.  
   Requests and replies are JSON.
2. `mise run core:build` builds `core/` with `go build -buildmode=c-archive` for arm64 and x86_64, joins them with `lipo`, wraps the result as `COnePassword.xcframework` with a module map, and prints the zip's checksum and size.  
   `mise run core:measure` also times the first client.
3. The binary is versioned by the content of `core/`, not by the package version.  
   Its release tag is `core-` and the first 12 hex digits of the git tree hash of `core/` (`mise run core:tag`).
4. The `Core` workflow (`.github/workflows/core.yml`) builds the binary on a GitHub-hosted macOS runner when a pull request changes `core/`.  
   It attaches the zip to a prerelease with that tag, and records the zip size and the first client's start-up time in the release notes.
5. `Package.swift` names that release in its `binaryTarget`.  
   After the workflow publishes a release for a new `core/`, run `mise run core:pin`: it downloads the zip, computes the checksum, and rewrites the url and checksum in `Package.swift`.
6. The `core:check` task, part of `mise run check`, fails when the tag in `Package.swift` differs from the one for `core/` at HEAD.

The package's own releases (`v*` tags, made by verctl) are separate from the `core-*` prereleases.  
After a release, a throwaway package that depends on the released version must build and link on a GitHub-hosted runner.

## Develop

Swift comes from Xcode 27, and the other tools are pinned in `mise.toml`.  
CI runs `mise run check`, which runs the repository checks, `swift build` and `swift test`.

## Licence

This package is licensed under the GNU Affero General Public License, version 3.  
The 1Password Go SDK that it builds on is licensed under the MIT licence.

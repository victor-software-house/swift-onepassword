# swift-onepassword

A Swift binding of [1Password's Go SDK](https://github.com/1password/onepassword-sdk-go) for macOS.
It reads vaults and items, and writes items, with a service account token, with no 1Password CLI and no helper process.

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
        for overview in try await client.items(inVault: vault.id) where overview.category == .sshKey {
            let item = try await client.item(overview.id, inVault: vault.id)
            print(item.title, item.fields.map(\.title))
        }
    }
} catch {
    // `error.code` is `.authenticationFailed`, `.rateLimited`, `.invalidResponse` or `.requestFailed`.
    // The message never contains the token.
    print(error)
}
```

| Call | Costs against 1Password's limits |
|:--|:--|
| `vaults()` | 1 read, and each vault's `contentVersion` rises when its contents change |
| `items(inVault:)` | 1 read |
| `item(_:inVault:)` | 2 reads |

`ItemCategory`, `ItemState`, `FieldType` and `ItemFailure` are open sets with constants such as `.sshKey`, `.active`, `.concealed` and `.notFound`.
A value that the SDK adds later still decodes, and compares by its `rawValue`.
`Item` and `ItemOverview` have `tags`.

The write calls take a vault ID:

| Call | Returns |
|:--|:--|
| `create(_:inVault:)` | one `ItemResult` for each `ItemContent`, in input order |
| `items(_:inVault:)` | one `ItemResult` for each ID, in input order |
| `update(_:inVault:to:)` | the updated `Item` |
| `delete(_:inVault:)` | the `ItemFailure` of each item that was not deleted, by ID; empty when all were |
| `archive(_:inVault:)` | nothing |

An `ItemResult` is `.item(Item)` or `.failure(ItemFailure)`, so one rejected item does not hide the others.
`update` sets the title, fields, sections, notes and tags.
It keeps the item's category, websites, files and document.
It fails when another writer changes the item between its read and its write.

A `Client` keeps one 1Password client until it is freed.
Its first creation loads 1Password's core, which takes about a second.
Keep the client and reuse it.

## The binary

1. `core/` is a Go module of one file, `shim.go`.
   It calls the SDK, pinned to an exact version in `core/go.mod`.
   It exports four C functions: `op_client_open`, `op_call`, `op_client_close` and `op_free`.
   Requests and responses are JSON.
2. `mise run core:build` builds `core/` with `go build -buildmode=c-archive` for arm64 and x86_64.
   It joins them with `lipo`, wraps the result as `COnePassword.xcframework` with a module map, and prints the zip's checksum and size.
   `mise run core:measure` also times the first client and reads its peak resident size.
3. The binary is versioned by the content of `core/`, not by the package version.
   Its release tag is `core-` and the first 12 hex digits of the git tree hash of `core/` (`mise run core:tag`).
4. The `Core` workflow (`.github/workflows/core.yml`) builds the binary on a GitHub-hosted macOS runner when a pull request changes `core/`.
   It attaches the zip to a prerelease with that tag.
   It records the zip size and the first client's start-up time in the release notes.
5. `Package.swift` names that release in its `binaryTarget`.
   After the workflow publishes a release for a new `core/`, run `mise run core:pin`.
   It downloads the zip, computes the checksum, and rewrites the url and checksum in `Package.swift`.
6. The `core:check` task, part of `mise run check`, fails when the tag in `Package.swift` differs from the one for `core/` at HEAD.

The package's own releases (`v*` tags, made by verctl) are separate from the `core-*` prereleases.
After a release, a throwaway package that depends on the released version must build and link on a GitHub-hosted runner.

## Cost

The numbers are from an Apple M4 Pro.
The `Benchmarks` workflow posts the same ones for a GitHub-hosted runner in its job summary.

| What | Cost |
|:--|:--|
| The first `Client.init` of a process | 1.2 s, and 165 MiB at its peak |
| A call that fails before 1Password, round trip from Swift | 6 to 7 µs and 33 allocations, with none left allocated |
| The Go side of that call, with no cgo | 0.2 µs for an unknown client, 0.5 µs for an invalid request |
| Decoding a vault list, an item list or an SSH Key item | 5 to 10 µs |
| `COnePassword.xcframework.zip` | 26 MB |

The first client dominates:

- 1Password's core is a 9.5 MB WebAssembly module.
  wazero compiles it to machine code in one thread, which takes 1.17 s of the 1.2 s.
- Garbage collector settings, thread count and profile-guided optimisation of the shim changed the start-up by less than 4%.
- A compilation cache on disk would cut it to 0.04 s in wazero's own test.
  The SDK has no option for one.
  A cache of machine code that the process runs is also a place to plant code, so the shim has none.
- A call after that costs microseconds, far below the time of a request to 1Password.
  Create the client once, as early as the program can, and keep it.
  A thousand calls and a thousand failing opens on one client left the Go heap at 19.8 MiB.
  The resident size stayed within 1 MiB.

## Tests and benchmarks

`mise run check` runs the repository checks, `go test -race` in `core/`, `swift build` and `swift test`.

The tests cover:

- the shim's dispatch with stub SDK clients, the typed errors, and a closed or unknown client;
- concurrent calls, and that every response is freed;
- the memory of a long-lived client;
- the decoding of fixtures.

`mise run live` also reads a real test vault.
It needs `OP_TEST_SERVICE_ACCOUNT_TOKEN` to be a read-only service account token for that vault, and skips otherwise.

The write tests use `OP_TEST_WRITE_TOKEN`, a service account that reads and writes only the vault "swift-onepassword writes", and skip without it.
They create SSH Key and Secure Note items tagged `swift-onepassword-test`, read, update and delete them, and delete what a crashed run left.

- CI runs both on pull requests from this repository and on every release run.
- The job summary shows the timings of a warm `vaults.list` and `items.get`.
- The read tests make about 45 calls to 1Password.

The benchmarks:

- `mise run bench:go` runs the Go benchmarks: a cold open in a fresh process, a warm open, and the dispatch of a call.
- `mise run bench:swift` runs the Swift benchmarks in `Benchmarks/`, a package of its own, so the library has no dependency on the benchmark package.
- The `Benchmarks` workflow runs both on a GitHub-hosted macOS runner.
  It fails when a Swift benchmark is worse than its threshold in `Benchmarks/Thresholds`.
- Each run uploads thresholds from its own numbers as the `thresholds` artifact.
  Commit them when a change makes a benchmark slower on purpose.

## Develop

Swift comes from Xcode 27, and the other tools are pinned in `mise.toml`.
CI runs `mise run check`.

## Licence

This package uses version 3 of the Affero General Public License.
The 1Password Go SDK that it builds on uses the MIT licence.

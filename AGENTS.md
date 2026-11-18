# AGENTS.md

swift-onepassword binds 1Password's Go SDK to Swift for macOS.  
A small Go file calls the SDK and exports C functions.  
`go build -buildmode=c-archive` turns it into a static library, shipped as an XCFramework that `Package.swift` names as a binary target.  
The Swift module `OnePassword` wraps the C functions in typed `async` calls.

## Work in this repository

1. This repository is public: no host names, client names, private repository links, account IDs, tokens or personal details in files, commits or pull requests.
2. The Go SDK is pinned to an exact version; a new SDK version is its own release.
3. Builds and tests run in CI on GitHub-hosted runners.
4. A pull request that changes behaviour adds a `.changeset` fragment, always a patch unless the operator picks otherwise.

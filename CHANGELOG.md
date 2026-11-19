# Changelog

## swift-onepassword 0.0.4

- - `Client` writes items: `create(_:inVault:)`, `items(_:inVault:)`, `update(_:inVault:to:)`, `delete(_:inVault:)` and `archive(_:inVault:)`.
    A batch call returns one `ItemResult` per item, in input order, so one failed item does not hide the others.
  - `Item` and `ItemOverview` have `tags`, which read as empty when the item has none ([`02bf45f`](https://github.com/victor-software-house/swift-onepassword/commit/02bf45fbac9125ed1b3776a3f25c36d93c2b662f)).

## swift-onepassword 0.0.3

- - `OnePasswordError` has a `code`: `authenticationFailed`, `rateLimited`, `invalidResponse` or `requestFailed`.  
    It conforms to `Equatable` and `LocalizedError`.
  - `ItemCategory`, `ItemState` and `FieldType` replace the strings in `category`, `state` and `Item.Field.type`.  
    Each is an open set with constants such as `.sshKey`, and a value the SDK adds later still decodes.
  - The identifier properties are `vaultID` and `sectionID`.
  - The methods are `vaults()`, `items(inVault:)` and `item(_:inVault:)` ([`e49277a`](https://github.com/victor-software-house/swift-onepassword/commit/e49277a2b1596c239b7637a9fa0dde2e5cb6fa8c)).

## swift-onepassword 0.0.2

- - `OnePasswordError.Kind.authentication` means 1Password refused the token or did not authenticate the request, such as a token revoked after the client opened.  
    An open that fails for want of a network or in a timeout reads as `other`.
  - `OnePasswordError.Kind.decoding` marks a reply the module cannot decode, so a caller can tell one bad item from a failed call.
  - `Item.Field.publicKey` holds the public key of an `SshKey` field, and is nil for any other field ([`cef2f93`](https://github.com/victor-software-house/swift-onepassword/commit/cef2f93088e2b20916441a86ab4b4cd3d01bd858)).

## swift-onepassword 0.0.1

- The `OnePassword` module reads vaults, items and one item's fields from 1Password with a service account token.  
  It binds 1Password's Go SDK 0.4.1 as a static library in the `COnePassword` XCFramework, so an app that links it stays one binary ([`1c3d82f`](https://github.com/victor-software-house/swift-onepassword/commit/1c3d82f41ea28b295e83030fc83a19dc17396071)).


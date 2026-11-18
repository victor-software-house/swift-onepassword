---
swift-onepassword: patch
---

- `OnePasswordError` has a `code`: `authenticationFailed`, `rateLimited`, `invalidResponse` or `requestFailed`.  
  It conforms to `Equatable` and `LocalizedError`.
- `ItemCategory`, `ItemState` and `FieldType` replace the strings in `category`, `state` and `Item.Field.type`.  
  Each is an open set with constants such as `.sshKey`, and a value the SDK adds later still decodes.
- The identifier properties are `vaultID` and `sectionID`.
- The methods are `vaults()`, `items(inVault:)` and `item(_:inVault:)`.

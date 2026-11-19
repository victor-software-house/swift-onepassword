---
swift-onepassword: patch
---

- `Client` writes items: `create(_:inVault:)`, `items(_:inVault:)`, `update(_:inVault:to:)`, `delete(_:inVault:)` and `archive(_:inVault:)`.
  A batch call returns one `ItemResult` per item, in input order, so one failed item does not hide the others.
- `Item` and `ItemOverview` have `tags`, which read as empty when the item has none.

---
swift-onepassword: patch
---

The `OnePassword` module reads vaults, items and one item's fields from 1Password with a service account token.  
It binds 1Password's Go SDK 0.4.1 as a static library in the `COnePassword` XCFramework, so an app that links it stays one binary.

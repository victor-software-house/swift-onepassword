# Changelog

## swift-onepassword 0.0.1

- The `OnePassword` module reads vaults, items and one item's fields from 1Password with a service account token.  
  It binds 1Password's Go SDK 0.4.1 as a static library in the `COnePassword` XCFramework, so an app that links it stays one binary ([`1c3d82f`](https://github.com/victor-software-house/swift-onepassword/commit/1c3d82f41ea28b295e83030fc83a19dc17396071)).


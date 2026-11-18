# Changelog

## swift-onepassword 0.0.2

- - `OnePasswordError.Kind.authentication` means 1Password refused the token or did not authenticate the request, such as a token revoked after the client opened.  
    An open that fails for want of a network or in a timeout reads as `other`.
  - `OnePasswordError.Kind.decoding` marks a reply the module cannot decode, so a caller can tell one bad item from a failed call.
  - `Item.Field.publicKey` holds the public key of an `SshKey` field, and is nil for any other field ([`cef2f93`](https://github.com/victor-software-house/swift-onepassword/commit/cef2f93088e2b20916441a86ab4b4cd3d01bd858)).

## swift-onepassword 0.0.1

- The `OnePassword` module reads vaults, items and one item's fields from 1Password with a service account token.  
  It binds 1Password's Go SDK 0.4.1 as a static library in the `COnePassword` XCFramework, so an app that links it stays one binary ([`1c3d82f`](https://github.com/victor-software-house/swift-onepassword/commit/1c3d82f41ea28b295e83030fc83a19dc17396071)).


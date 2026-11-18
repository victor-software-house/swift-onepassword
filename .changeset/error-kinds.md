---
swift-onepassword: patch
---

- `OnePasswordError.Kind.authentication` means 1Password refused the token or did not authenticate the request, such as a token revoked after the client opened.  
  An open that fails for want of a network or in a timeout reads as `other`.
- `OnePasswordError.Kind.decoding` marks a reply the module cannot decode, so a caller can tell one bad item from a failed call.
- `Item.Field.publicKey` holds the public key of an `SshKey` field, and is nil for any other field.

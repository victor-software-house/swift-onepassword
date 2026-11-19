---
swift-onepassword: patch
---

- `Item.Field.fingerprint` and `Item.Field.keyType` hold the fingerprint and the key type (`Ed25519`, or `RSA, {length}-bit`) of an `SshKey` field, and are nil for any other field.

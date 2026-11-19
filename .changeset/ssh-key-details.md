---
swift-onepassword: patch
---

`Item.Field.fingerprint` and `Item.Field.keyType` return the fingerprint and the key type (`Ed25519`, or `RSA, {length}-bit`) of an `SshKey` field, and nil for any other field.

# Proposal

## Why

The SDK computes three attributes for an `SshKey` field: the public key, its fingerprint and its key type.
`Item.Field` exposes only the public key, so a caller that wants to show or compare a key by its fingerprint or kind must compute them again.

## What Changes

- `Item.Field` gains `fingerprint` and `keyType`, both `String?`, read from the same `details.content` object as `publicKey`.
- `keyType` is a string and not an open-set struct: the SDK documents `Ed25519` and `RSA, {length}-bit`, so only one value is a constant.
- `Item.Field` encodes the three attributes under `details.content` when any is set, so a field decodes to what it encoded.
- The core passes the SDK's details through unchanged, so it needs no change.

## Capabilities

### New Capabilities

- `ssh-key-details`: the attributes an `SshKey` field exposes.

## Impact

- `Item.Field` and its initializer gain two parameters with nil defaults, so every existing call keeps compiling.
- The C interface and its JSON keep their shape.

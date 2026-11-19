# ssh-key-details Specification

## Purpose

An `SshKey` field returns the public key, the fingerprint and the key type that 1Password stores for it.

## Requirements

### Requirement: An SshKey field exposes its key attributes

An `Item.Field` of type `SshKey` SHALL expose `publicKey`, `fingerprint` and `keyType` as the SDK computes them.
Each attribute SHALL be nil when the field has no details, the details have no content, or the content lacks that attribute.
A field of another type SHALL expose none of them.

#### Scenario: An Ed25519 key

- **WHEN** an item has an `SshKey` field whose details carry a public key, a fingerprint and the key type `Ed25519`
- **THEN** the field's `publicKey`, `fingerprint` and `keyType` equal those values

#### Scenario: A key type with a length

- **WHEN** the details carry the key type `RSA, 4096-bit`
- **THEN** the field's `keyType` is `RSA, 4096-bit`

#### Scenario: A field without details

- **WHEN** an `SshKey` field has no details, or details whose content is null
- **THEN** its three attributes are nil

### Requirement: A field encodes the attributes it decodes

`Item.Field` SHALL encode every attribute that is set under `details.content`, and SHALL write no details when none is set.

#### Scenario: Each attribute alone

- **WHEN** a field with only one of the three attributes is encoded and decoded
- **THEN** the result equals the field

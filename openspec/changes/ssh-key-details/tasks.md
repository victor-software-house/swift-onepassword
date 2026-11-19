# Tasks

## 1. Code

- [ ] 1.1 Add `fingerprint` and `keyType` to `Item.Field`, read and written beside `publicKey`.
  Verify `swift test` passes in CI.
  The decoding tests read the fixtures for each key type, a field without details and a null content.
  The round trip tests cover all attributes and each one alone.

## 2. Release

- [ ] 2.1 Add a changeset.
  Verify the Version PR lists the change.

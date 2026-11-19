# Tasks

## 1. Code

- [x] 1.1 Add `fingerprint` and `keyType` to `Item.Field`, read and written beside `publicKey`.
  Verify `swift test` passes in CI.
  The decoding tests read the fixtures for each key type, a field without details and a null content.
  The round trip tests cover all attributes and each one alone.
  - 2026-11-19 UTC: [CI run 44522274648][ci-44522274648] passed at 2c7cad6, and [Benchmarks run 44522274614][bench-44522274614] passed.
    The Rivest–Shamir–Adleman (RSA) case has its own fixture, so the SSH key benchmark reads the same input as on main.

## 2. Release

- [ ] 2.1 Add a changeset.
  Verify the Version PR lists the change.

[ci-44522274648]: https://github.com/victor-software-house/swift-onepassword/actions/runs/44522274648
[bench-44522274614]: https://github.com/victor-software-house/swift-onepassword/actions/runs/44522274614

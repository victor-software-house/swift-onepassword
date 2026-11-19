# Write items

## Why

signd's backup copies each shareable key into a 1Password vault ([signd's onepassword-backup change][signd]).
It needs to create, update, archive and delete the items it owns.
This package reads vaults and items today, and has no write call.

## What Changes

- `Client` gains five calls over onepassword-sdk-go v0.4.1.
  They create, read and delete many items, and update or archive one.
- An update reads the item and writes it back in one core call.
  So the parts this package does not model, such as websites and files, stay as they were.
- `Item` and `ItemOverview` gain their tags.
- A batch call returns one result per item, in input order, so one failed item does not hide the others.
- Live tests write to their own vault with their own service account; the read tests keep the read-only account.

## Capabilities

### New Capabilities

- `item-writes`: the write calls, their results and their live tests.

## Impact

- The C interface gains five methods; every existing method and result keeps its shape.
- CI passes the secret `OP_TEST_WRITE_TOKEN` to the live tests.

[signd]: https://github.com/victor-software-house/signd/tree/835a9be6b32651335bc427ca46e70b0b78307a17/openspec/changes/onepassword-backup

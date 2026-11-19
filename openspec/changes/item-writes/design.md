# Design

## Context

The core in `core/shim.go` maps a JSON request to one SDK call and returns its JSON.
onepassword-sdk-go v0.4.1 offers `CreateAll`, `GetAll`, `Put`, `DeleteAll` and `Archive` on its items API.
Its batch calls return a `Response` per item with either `content` or `error`, and an error's message is an unexported field, which `json.Marshal` drops.

## Decisions

### 1. Core methods

| Method | Request fields | SDK call | Result |
|:--|:--|:--|:--|
| `items.createAll` | `vaultId`, `items` | `CreateAll` | one entry per item, in order |
| `items.getAll` | `vaultId`, `itemIds` | `GetAll` | one entry per id, in order |
| `items.update` | `vaultId`, `itemId`, `content` | `Get`, then `Put` | the updated item |
| `items.deleteAll` | `vaultId`, `itemIds` | `DeleteAll` | one entry per id that failed |
| `items.archive` | `vaultId`, `itemId` | `Archive` | none |

An entry is `{"item": ...}` or `{"failure": "<type>"}`, where the type is the SDK's failure type, such as `itemValidationError`.
The core writes this shape itself, so no failure loses its type.

Each method answers `invalidRequest` when a field it needs is missing or empty, before any SDK call.
The core does not split a batch; the caller keeps each batch within the SDK's limits.

### 2. Unset parts of an updated item

`content` sets the title, fields, sections, notes and tags.
The core reads the item, replaces those five, and writes it back with `Put`.
The category, version, websites, files and document come from the item it read.

A change between the read and the write makes `Put` fail with an incorrect version, which the call returns as `requestFailed` with the SDK's message.

### 3. Swift types

| Type | Purpose |
|:--|:--|
| `ItemContent` | the category, title, fields, sections, notes and tags of a new or updated item |
| `ItemFailure` | a failure type, open like `ItemCategory` |
| `ItemResult` | `.item(Item)` or `.failure(ItemFailure)` |

`Item` and `ItemOverview` gain `tags`, and a missing or null list reads as empty.
An update ignores `ItemContent`'s category.

| Call | Returns |
|:--|:--|
| `create(_:inVault:)` | `[ItemResult]` in input order |
| `items(_:inVault:)` | `[ItemResult]` in input order |
| `update(_:inVault:to:)` | `Item` |
| `delete(_:inVault:)` | `[String: ItemFailure]`, empty when every item was deleted |
| `archive(_:inVault:)` | nothing |

### 4. Live tests

The read tests keep `OP_TEST_SERVICE_ACCOUNT_TOKEN`, which reads "signd test" only.
The write tests use `OP_TEST_WRITE_TOKEN`, a service account that can read and write only the vault "swift-onepassword writes", and skip without it.

A run tags its items `swift-onepassword-test` and deletes them at its end, pass or fail.
It first deletes tagged items that a crashed run left behind.

The SDK refuses to delete an archived item and has no unarchive, so the live suite does not archive.

The SSH Key item's private key is an Ed25519 key that the test makes, in the Public-Key Cryptography Standards (PKCS) 8 format.

## Risks

- A lost race in an update returns an error rather than retrying; the caller decides.

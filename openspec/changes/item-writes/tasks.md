# Tasks

## 1. Code

- [ ] 1.1 Add the five core methods by design decision 1, with update by decision 2.
  Verify Go unit tests with stub items APIs for each method, each missing field, and a batch with one failure.
- [ ] 1.2 Add the Swift types and calls by decision 3, and `tags` to `Item` and `ItemOverview`.
  Verify decoding tests from fixtures for a batch result, a failure, and an item without tags.
- [ ] 1.3 Add the live write tests by decision 4, and pass `OP_TEST_WRITE_TOKEN` to them in CI.
  Verify the live job creates, reads, updates, archives and deletes items, and leaves none behind.

## 2. Release

- [ ] 2.1 Add a changeset, and update the README's API section.
  Verify the Version PR lists the change.

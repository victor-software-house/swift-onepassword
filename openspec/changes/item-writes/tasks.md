# Tasks

## 1. Code

- [x] 1.1 Add the five core methods by design decision 1, with update by decision 2.
  Verify Go unit tests with stub items APIs for each method, each missing field, and a batch with one failure.
  - 2026-11-19 UTC: `go test -race` in `core/` passed in the [CI run][ci-build].
    It covers each method, each missing field, two batches with one failure, and an update that keeps websites, files and document.
- [x] 1.2 Add the Swift types and calls by decision 3, and `tags` to `Item` and `ItemOverview`.
  Verify decoding tests from fixtures for a batch result, a failure, and an item without tags.
  - 2026-11-19 UTC: `swift test` passed in the [CI run][ci-build].
    The fixture tests cover a batch result with two failure types, a delete failure map, null and missing tags, and the request of each call.
- [x] 1.3 Add the live write tests by decision 4, and pass `OP_TEST_WRITE_TOKEN` to them in CI.
  Verify the live job creates, reads, updates and deletes items, and leaves none behind.
  - 2026-11-19 UTC: the live job passed in the [CI run][ci-build].
    The suite does not archive, because the SDK cannot delete an archived item; the Go tests cover `items.archive`.

## 2. Release

- [ ] 2.1 Add a changeset, and update the README's API section.
  Verify the Version PR lists the change.
  - 2026-11-19 UTC: `.changeset/item-writes.md` and the README section are in [pull request 18][pr-18].
    The Version PR exists only after the merge, so it is not yet read.

[ci-build]: https://github.com/victor-software-house/swift-onepassword/actions/runs/44484809217/job/135425678134
[pr-18]: https://github.com/victor-software-house/swift-onepassword/pull/18

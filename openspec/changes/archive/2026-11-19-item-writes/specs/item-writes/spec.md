# item-writes

## ADDED Requirements

### Requirement: Batch writes report each item

`create` and `items` SHALL return one result per input, in input order.
`delete` SHALL return the failure of each item it could not delete, and nothing for the others.

#### Scenario: One invalid item in a batch

- **WHEN** `create` gets two items and the SDK rejects the second
- **THEN** the first result is the created item and the second is a failure with the SDK's type

### Requirement: An update keeps the fields it does not set

`update` SHALL set the item's title, fields, sections, notes and tags, and SHALL keep its category, websites, files and document.

#### Scenario: An item with a website

- **WHEN** an item with a website is updated with a new title
- **THEN** the item keeps its website

### Requirement: A request with a missing field fails before the SDK

Each write method SHALL answer `invalidRequest` when a field it needs is missing or empty, and SHALL make no SDK call.

#### Scenario: Delete with no ids

- **WHEN** `items.deleteAll` gets an empty `itemIds`
- **THEN** the response is `invalidRequest`

### Requirement: Live write tests clean up

The live write tests SHALL delete every item they create, pass or fail, and SHALL first delete items a crashed run left.

#### Scenario: A failed run

- **WHEN** an expectation fails after an item is created
- **THEN** the vault contains no item tagged `swift-onepassword-test` once the suite ends

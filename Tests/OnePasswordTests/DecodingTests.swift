import Foundation
import Testing

@testable import OnePassword

struct DecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.resourceURL).appending(path: "Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    @Test func vaultList() throws {
        let response = try CoreJSON.decode(CoreResponse<[VaultOverview]>.self, from: fixture("vault-list"))
        let vaults = try #require(response.result)

        #expect(vaults.map(\.title) == ["SSH keys", "Other"])
        #expect(vaults[0].id == "aaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(vaults[0].contentVersion == 41)
        // Nine fractional digits, as Go writes a time value.
        #expect(abs(vaults[0].updatedAt.timeIntervalSince1970 - 1_794_918_645.123456789) < 0.001)
        // An offset instead of Z.
        #expect(vaults[1].updatedAt.timeIntervalSince1970 == 1_794_918_645.5)
    }

    @Test func itemList() throws {
        let response = try CoreJSON.decode(CoreResponse<[ItemOverview]>.self, from: fixture("item-list"))
        let items = try #require(response.result)

        #expect(items.map(\.category) == [.sshKey, .secureNote])
        #expect(items.map(\.state) == [.active, .archived])
        #expect(items[0].vaultID == "aaaaaaaaaaaaaaaaaaaaaaaaaa")
        // No fraction.
        #expect(items[0].updatedAt.timeIntervalSince1970 == 1_794_918_645)
        #expect(items[1].updatedAt.timeIntervalSince1970 == 1_794_816_900.25)
    }

    @Test func sshKeyItem() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-ssh-key"))
        let item = try #require(response.result)

        #expect(item.category == .sshKey)
        #expect(item.version == 7)
        #expect(item.sections == [Item.Section(id: "signd", title: "signd")])
        #expect(item.fields.map(\.id) == ["private_key", "public_key", "hosts", "rsa_key"])
        #expect(item.fields[0].type == .sshKey)
        #expect(item.fields[0].value == "PLACEHOLDER-PRIVATE-KEY-NOT-A-KEY")
        #expect(item.fields[0].sectionID == nil)
        #expect(item.fields[2].sectionID == "signd")
        #expect(item.fields[2].value == "git.example.com")
    }

    @Test func keyAttributesComeFromTheDetailsOfAnSshKeyField() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-ssh-key"))
        let fields = try #require(response.result).fields

        #expect(fields[0].publicKey == "ssh-ed25519 AAAAFAKEFAKEFAKEFAKE fake-key-for-tests")
        #expect(fields[0].fingerprint == "SHA256:FAKEFINGERPRINT")
        #expect(fields[0].keyType == "Ed25519")
        // No details.
        #expect(fields[1].publicKey == nil)
        #expect(fields[1].fingerprint == nil)
        #expect(fields[1].keyType == nil)
        #expect(fields[2].publicKey == nil)
        #expect(fields[2].fingerprint == nil)
        #expect(fields[2].keyType == nil)
        // A key type that names a length.
        #expect(fields[3].fingerprint == "SHA256:FAKERSAFINGERPRINT")
        #expect(fields[3].keyType == "RSA, 4096-bit")
    }

    @Test func fieldsWithoutAnSshKeyHaveNoKeyAttributes() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-field-details"))
        let fields = try #require(response.result).fields

        // Details of another type, an SshKey field whose content is null, and no details.
        #expect(fields.map(\.id) == ["otp", "empty_key", "no_details"])
        #expect(fields.map(\.publicKey) == [nil, nil, nil])
        #expect(fields.map(\.fingerprint) == [nil, nil, nil])
        #expect(fields.map(\.keyType) == [nil, nil, nil])
    }

    @Test func fieldRoundTripsItsKeyAttributes() throws {
        let field = Item.Field(
            id: "k", title: "k", type: .sshKey, value: "v", sectionID: "s", publicKey: "ssh-ed25519 AAAA",
            fingerprint: "SHA256:AAAA", keyType: "Ed25519")
        let data = try JSONEncoder().encode(field)

        #expect(try JSONDecoder().decode(Item.Field.self, from: data) == field)
    }

    @Test func fieldRoundTripsEachKeyAttributeAlone() throws {
        let fields = [
            Item.Field(id: "p", title: "p", type: .sshKey, value: "v", publicKey: "ssh-ed25519 AAAA"),
            Item.Field(id: "f", title: "f", type: .sshKey, value: "v", fingerprint: "SHA256:AAAA"),
            Item.Field(id: "t", title: "t", type: .sshKey, value: "v", keyType: "RSA, 2048-bit"),
        ]

        for field in fields {
            let data = try JSONEncoder().encode(field)
            #expect(try JSONDecoder().decode(Item.Field.self, from: data) == field)
        }
    }

    @Test func aResponseThatDoesNotDecodeIsAnInvalidResponse() {
        let error = #expect(throws: OnePasswordError.self) {
            _ = try CoreJSON.decode(CoreResponse<Item>.self, from: Data(#"{"result": {"id": 1}}"#.utf8))
        }

        #expect(error?.code == .invalidResponse)
        #expect(error?.message == "the response could not be decoded")
    }

    @Test func nullSlicesReadAsEmpty() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-no-sections"))
        let item = try #require(response.result)

        #expect(item.fields.isEmpty)
        #expect(item.sections.isEmpty)
    }

    @Test func tagsReadAsEmptyWhenNullOrMissing() throws {
        let listed = try #require(
            try CoreJSON.decode(CoreResponse<[ItemOverview]>.self, from: fixture("item-list")).result)
        let bare = try #require(
            try CoreJSON.decode(CoreResponse<[ItemOverview]>.self, from: fixture("item-overview-no-tags")).result)
        let nullTags = try #require(
            try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-ssh-key")).result)
        let missingTags = try #require(
            try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-no-sections")).result)

        // Null, a list, and a missing key, for an overview and an item.
        #expect(listed.map(\.tags) == [[], ["fake"]])
        #expect(bare.map(\.tags) == [[]])
        #expect(nullTags.tags.isEmpty)
        #expect(missingTags.tags.isEmpty)
    }

    @Test func batchResultKeepsOrderAndFailureTypes() throws {
        let response = try CoreJSON.decode(CoreResponse<[ItemResult]>.self, from: fixture("batch-result"))
        let results = try #require(response.result)

        #expect(results.count == 3)
        guard case .item(let item) = results[0] else {
            Issue.record("the first result is not an item")
            return
        }
        #expect(item.title == "Deploy key")
        #expect(item.tags == ["swift-onepassword-test"])
        #expect(results[1] == .failure(.validationError))
        // A type that the SDK adds later still decodes.
        #expect(results[2] == .failure(ItemFailure(rawValue: "somethingNew")))
    }

    @Test func aBatchEntryWithNeitherAnItemNorAFailureIsAnInvalidResponse() {
        let error = #expect(throws: OnePasswordError.self) {
            _ = try CoreJSON.decode(CoreResponse<[ItemResult]>.self, from: Data(#"{"result": [{}]}"#.utf8))
        }

        #expect(error?.code == .invalidResponse)
    }

    @Test func deleteFailuresMapEachIDToItsType() throws {
        let failed = try #require(
            try CoreJSON.decode(CoreResponse<[String: ItemFailure]>.self, from: fixture("delete-failures")).result)
        let none = try #require(
            try CoreJSON.decode(CoreResponse<[String: ItemFailure]>.self, from: fixture("delete-all-deleted")).result)

        #expect(failed == ["dddddddddddddddddddddddddd": .permissionError])
        #expect(none.isEmpty)
    }

    private func requestObject(_ request: CoreRequest) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: Data(CoreJSON.encode(request).utf8)) as? NSDictionary)
    }

    private func fixtureObject(_ name: String) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: fixture(name)) as? NSDictionary)
    }

    private let content = ItemContent(
        category: .secureNote, title: "t",
        fields: [Item.Field(id: "f", title: "F", type: .concealed, value: "x", sectionID: "s")],
        sections: [Item.Section(id: "s", title: "S")], notes: "n", tags: ["a"])

    @Test func createRequestHasTheItems() throws {
        let request = CoreRequest(method: .createItems, vaultID: "v", items: [content])

        #expect(try requestObject(request) == fixtureObject("request-create-items"))
    }

    @Test func getRequestHasTheItemIDs() throws {
        let request = CoreRequest(method: .getItems, vaultID: "v", itemIDs: ["a", "b"])

        #expect(try requestObject(request) == fixtureObject("request-get-items"))
    }

    @Test func updateRequestHasTheContent() throws {
        let request = CoreRequest(method: .updateItem, vaultID: "v", itemID: "i", content: content)

        #expect(try requestObject(request) == fixtureObject("request-update-item"))
    }

    @Test func deleteRequestHasTheItemIDs() throws {
        let request = CoreRequest(method: .deleteItems, vaultID: "v", itemIDs: ["a", "b"])

        #expect(try requestObject(request) == fixtureObject("request-delete-items"))
    }

    @Test func archiveRequestHasTheItemID() throws {
        let request = CoreRequest(method: .archiveItem, vaultID: "v", itemID: "i")

        #expect(try requestObject(request) == fixtureObject("request-archive-item"))
    }

    @Test func errorCodesMap() throws {
        let response = try CoreJSON.decode(CoreResponse<[VaultOverview]>.self, from: fixture("error-rate-limited"))

        #expect(response.error?.onePasswordError.code == .rateLimited)
        #expect(CoreError(code: "authenticationFailed", message: "x").onePasswordError.code == .authenticationFailed)
        #expect(CoreError(code: "requestFailed", message: "x").onePasswordError.code == .requestFailed)
        #expect(CoreError(code: "invalidRequest", message: "x").onePasswordError.code == .requestFailed)
        #expect(CoreError(code: "unknownClient", message: "x").onePasswordError.code == .requestFailed)
        #expect(CoreError(code: "somethingNew", message: "x").onePasswordError.code == .requestFailed)
    }

    @Test func requestIsJSON() throws {
        let json = CoreJSON.encode(CoreRequest(method: .getItem, vaultID: "v", itemID: "i"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])

        #expect(object == ["method": "items.get", "vaultId": "v", "itemId": "i"])
    }

    @Test(arguments: [
        ("1970-01-01T00:00:00Z", 0.0),
        ("2024-02-29T00:00:00Z", 1_709_164_800),
        ("2026-11-17T12:30:45Z", 1_794_918_645),
        ("2026-11-17T12:30:45.5Z", 1_794_918_645.5),
        ("2026-11-17T12:30:45.123456789012Z", 1_794_918_645.123456789),
        ("2026-11-17T12:30:45+05:30", 1_794_898_845),
        ("2026-11-17T12:30:45.25-03:00", 1_794_929_445.25),
    ])
    func timestamps(text: String, seconds: Double) throws {
        let date = try #require(RFC3339.date(from: text))

        #expect(abs(date.timeIntervalSince1970 - seconds) < 1e-6)
    }

    @Test(arguments: [
        "", "garbage", "2026-11-17", "2026-11-17T12:30:45", "2026-11-17T12:30:45.Z", "2026-13-17T12:30:45Z",
        "2026-11-17T25:30:45Z", "2026-11-17T12:30:45+0530", "2026-11-17T12:30:45Zextra", "2026-11-17 12:30:45Z",
    ])
    func malformedTimestamps(text: String) {
        #expect(RFC3339.date(from: text) == nil)
    }
}

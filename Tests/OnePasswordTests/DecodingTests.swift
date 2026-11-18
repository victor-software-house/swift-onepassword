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
        #expect(item.fields.map(\.id) == ["private_key", "public_key", "hosts"])
        #expect(item.fields[0].type == .sshKey)
        #expect(item.fields[0].value == "PLACEHOLDER-PRIVATE-KEY-NOT-A-KEY")
        #expect(item.fields[0].sectionID == nil)
        #expect(item.fields[2].sectionID == "signd")
        #expect(item.fields[2].value == "git.example.com")
    }

    @Test func publicKeyComesFromTheDetailsOfAnSshKeyField() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-ssh-key"))
        let fields = try #require(response.result).fields

        #expect(fields[0].publicKey == "ssh-ed25519 AAAAFAKEFAKEFAKEFAKE fake-key-for-tests")
        // No details.
        #expect(fields[1].publicKey == nil)
        #expect(fields[2].publicKey == nil)
    }

    @Test func fieldsWithoutAnSshKeyHaveNoPublicKey() throws {
        let response = try CoreJSON.decode(CoreResponse<Item>.self, from: fixture("item-field-details"))
        let fields = try #require(response.result).fields

        // Details of another type, an SshKey field whose content is null, and no details.
        #expect(fields.map(\.id) == ["otp", "empty_key", "no_details"])
        #expect(fields.map(\.publicKey) == [nil, nil, nil])
    }

    @Test func fieldRoundTripsItsPublicKey() throws {
        let field = Item.Field(
            id: "k", title: "k", type: .sshKey, value: "v", sectionID: "s", publicKey: "ssh-ed25519 AAAA")
        let data = try JSONEncoder().encode(field)

        #expect(try JSONDecoder().decode(Item.Field.self, from: data) == field)
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

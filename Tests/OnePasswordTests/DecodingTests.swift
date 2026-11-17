import Foundation
import Testing

@testable import OnePassword

struct DecodingTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.resourceURL).appending(path: "Fixtures/\(name).json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func vaultList() throws {
        let reply = try Wire.decode(Wire.Reply<[VaultOverview]>.self, from: fixture("vault-list"))
        let vaults = try #require(reply.result)

        #expect(vaults.map(\.title) == ["SSH keys", "Other"])
        #expect(vaults[0].id == "aaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(vaults[0].contentVersion == 41)
        // Nine fractional digits, as Go writes a time.Time.
        #expect(abs(vaults[0].updatedAt.timeIntervalSince1970 - 1_794_918_645.123456789) < 0.001)
        // An offset instead of Z.
        #expect(vaults[1].updatedAt.timeIntervalSince1970 == 1_794_918_645.5)
    }

    @Test func itemList() throws {
        let reply = try Wire.decode(Wire.Reply<[ItemOverview]>.self, from: fixture("item-list"))
        let items = try #require(reply.result)

        #expect(items.map(\.category) == ["SshKey", "SecureNote"])
        #expect(items.map(\.state) == ["active", "archived"])
        #expect(items[0].vaultId == "aaaaaaaaaaaaaaaaaaaaaaaaaa")
        // No fraction.
        #expect(items[0].updatedAt.timeIntervalSince1970 == 1_794_918_645)
        #expect(items[1].updatedAt.timeIntervalSince1970 == 1_794_816_900.25)
    }

    @Test func sshKeyItem() throws {
        let reply = try Wire.decode(Wire.Reply<Item>.self, from: fixture("item-ssh-key"))
        let item = try #require(reply.result)

        #expect(item.category == "SshKey")
        #expect(item.version == 7)
        #expect(item.sections == [Item.Section(id: "signd", title: "signd")])
        #expect(item.fields.map(\.id) == ["private_key", "public_key", "hosts"])
        #expect(item.fields[0].fieldType == "SshKey")
        #expect(item.fields[0].value == "PLACEHOLDER-PRIVATE-KEY-NOT-A-KEY")
        #expect(item.fields[0].sectionId == nil)
        #expect(item.fields[2].sectionId == "signd")
        #expect(item.fields[2].value == "git.example.com")
    }

    @Test func nullSlicesReadAsEmpty() throws {
        let reply = try Wire.decode(Wire.Reply<Item>.self, from: fixture("item-no-sections"))
        let item = try #require(reply.result)

        #expect(item.fields.isEmpty)
        #expect(item.sections.isEmpty)
    }

    @Test func errorKindsMap() throws {
        let reply = try Wire.decode(Wire.Reply<[VaultOverview]>.self, from: fixture("error-rate-limited"))

        #expect(reply.error?.error.kind == .rateLimited)
        #expect(Wire.Failure(kind: "badRequest", message: "x").error.kind == .other)
        #expect(Wire.Failure(kind: "unknownHandle", message: "x").error.kind == .other)
    }

    @Test func requestIsJSON() throws {
        let json = Wire.encode(Wire.Request(method: "items.get", vaultId: "v", itemId: "i"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])

        #expect(object == ["method": "items.get", "vaultId": "v", "itemId": "i"])
    }
}

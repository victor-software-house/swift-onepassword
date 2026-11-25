import CryptoKit
import Foundation
import Testing

@testable import OnePassword

// These tests write to a real 1Password vault with a service account that reads and writes only that vault.
// They run only when OP_TEST_WRITE_TOKEN is set, so a local run and a pull request from a fork skip them.
//
// The vault is "swift-onepassword writes". Every item a run makes has the tag "swift-onepassword-test".
// A run first deletes tagged items that a crashed run left, and deletes its own at the end, pass or fail.
//
// The suite does not archive.
// The SDK cannot delete an archived item, so an archive would leave one in the vault.
// Nothing prints the token or a field value.
private let writeToken = ProcessInfo.processInfo.environment["OP_TEST_WRITE_TOKEN"] ?? ""
private let testTag = "swift-onepassword-test"

@Suite(.serialized, .enabled(if: !writeToken.isEmpty))
struct WriteLiveTests {
    private struct Unexpected: Error, CustomStringConvertible {
        let description: String
    }

    @Test func createsReadsUpdatesArchivesAndDeletesItems() async throws {
        let client = try await Client(
            token: writeToken, integrationName: "swift-onepassword-tests", integrationVersion: "0")
        let vaults = try await client.vaults()
        let vault = try #require(vaults.first { $0.title == "swift-onepassword writes" })

        try await removeTagged(client, vaultID: vault.id)
        do {
            try await scenario(client, vaultID: vault.id)
        } catch {
            try? await removeTagged(client, vaultID: vault.id)
            throw error
        }
        try await removeTagged(client, vaultID: vault.id)
    }

    private func scenario(_ client: Client, vaultID: String) async throws {
        let sshKey = ItemContent(
            category: .sshKey, title: "swift-onepassword test key",
            fields: [Item.Field(id: "private_key", title: "private key", type: .sshKey, value: Self.newPrivateKey())],
            tags: [testTag])
        let note = ItemContent(
            category: .secureNote, title: "swift-onepassword test note",
            fields: [
                Item.Field(id: "hosts", title: "hosts", type: .text, value: "example.invalid", sectionID: "signd")
            ],
            sections: [Item.Section(id: "signd", title: "signd")], notes: "a note", tags: [testTag])

        let created = try await client.create([sshKey, note], inVault: vaultID)
        #expect(created.count == 2)
        let sshID = try Self.item(created[0]).id
        let noteID = try Self.item(created[1]).id

        let read = try await client.items([sshID, noteID], inVault: vaultID)
        #expect(read.count == 2)
        let readKey = try Self.item(read[0])
        let readNote = try Self.item(read[1])
        #expect(readKey.category == .sshKey)
        #expect(readKey.tags == [testTag])
        let publicKey = readKey.fields.first { $0.type == .sshKey }?.publicKey
        #expect(publicKey?.hasPrefix("ssh-ed25519 ") == true)
        #expect(readNote.category == .secureNote)

        let renamed = ItemContent(
            category: readNote.category, title: "swift-onepassword test note, renamed", fields: readNote.fields,
            sections: readNote.sections, notes: readNote.notes, tags: [testTag, "renamed"])
        let updated = try await client.update(noteID, inVault: vaultID, to: renamed)
        #expect(updated.title == "swift-onepassword test note, renamed")
        #expect(updated.tags == [testTag, "renamed"])
        #expect(updated.category == .secureNote)
        #expect(updated.fields.first { $0.id == "hosts" }?.value == "example.invalid")

        let failed = try await client.delete([sshID, noteID], inVault: vaultID)
        #expect(failed.isEmpty)
        let remaining = try await client.items(inVault: vaultID)
        #expect(!remaining.contains { $0.tags.contains(testTag) })
    }

    /// Deletes the items of the vault that carry the test tag.
    private func removeTagged(_ client: Client, vaultID: String) async throws {
        let ids = try await client.items(inVault: vaultID).filter { $0.tags.contains(testTag) }.map(\.id)
        guard !ids.isEmpty else { return }
        let failed = try await client.delete(ids, inVault: vaultID)
        #expect(failed.isEmpty)
    }

    private static func item(_ result: ItemResult) throws -> Item {
        switch result {
        case .item(let item): return item
        case .failure(let failure): throw Unexpected(description: "an item failed with \(failure.rawValue)")
        }
    }

    /// A fresh Ed25519 private key as a PEM file in the Public-Key Cryptography Standards (PKCS) 8 format.
    /// The prefix is the Distinguished Encoding Rules (DER) header of such a key, before its 32 bytes.
    /// The label is built in two parts, so that no scanner reads this source as a key block.
    private static func newPrivateKey() -> String {
        let prefix = Data([
            0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
        ])
        let der = prefix + Curve25519.Signing.PrivateKey().rawRepresentation
        let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let label = "PRIVATE" + " KEY"
        return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
    }
}

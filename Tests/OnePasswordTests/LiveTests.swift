import Foundation
import Testing

@testable import OnePassword

// These tests read a real 1Password vault with a read-only service account.
// They run only when OP_TEST_SERVICE_ACCOUNT_TOKEN is set, so a local run and a pull request from a fork skip them.
//
// The account reads one vault, "signd test", with one SSH Key item, "test-key".
// Nothing prints the token or a field value other than hosts.
// An expectation sees booleans for the key itself.
private let token = ProcessInfo.processInfo.environment["OP_TEST_SERVICE_ACCOUNT_TOKEN"] ?? ""

@Suite(.serialized, .enabled(if: !token.isEmpty))
struct LiveTests {
    private func open() async throws(OnePasswordError) -> Client {
        try await Client(token: token, integrationName: "swift-onepassword-tests", integrationVersion: "0")
    }

    @Test func readsTheTestVault() async throws {
        let client = try await open()

        let vaults = try await client.vaults()
        let vault = try #require(vaults.first { $0.title == "signd test" })
        #expect(vault.contentVersion > 0)

        let items = try await client.items(inVault: vault.id)
        let overview = try #require(items.first { $0.title == "test-key" })
        #expect(overview.category == .sshKey)
        #expect(overview.state == .active)

        let item = try await client.item(overview.id, inVault: vault.id)
        #expect(item.category == .sshKey)
        #expect(item.vaultID == vault.id)
        let hosts = item.fields.first { $0.title == "hosts" || $0.id == "hosts" }?.value
        #expect(hosts == "example.invalid")
        let hasPrivateKey = item.fields.contains { $0.type == .sshKey && !$0.value.isEmpty }
        #expect(hasPrivateKey)
        let publicKey = item.fields.first { $0.type == .sshKey }?.publicKey
        #expect(publicKey?.hasPrefix("ssh-ed25519 ") == true)
    }

    /// Times a warm vaults.list and items.get on the network, with no gate, because the network
    /// varies. The report goes to the file named by OP_LIVE_REPORT, for the job summary.
    @Test func timesWarmCalls() async throws {
        let client = try await open()
        let vaults = try await client.vaults()
        let vault = try #require(vaults.first { $0.title == "signd test" })
        let items = try await client.items(inVault: vault.id)
        let overview = try #require(items.first { $0.title == "test-key" })
        _ = try await client.item(overview.id, inVault: vault.id)

        let clock = ContinuousClock()
        var listing: [Duration] = []
        var getting: [Duration] = []
        for _ in 0..<20 {
            try await listing.append(clock.measure { _ = try await client.vaults() })
            try await getting.append(clock.measure { _ = try await client.item(overview.id, inVault: vault.id) })
        }

        let report = """
            | Live call, warm client | Samples | p50 | p95 |
            |:--|--:|--:|--:|
            | vaults.list | \(listing.count) | \(Self.percentile(listing, 50)) | \(Self.percentile(listing, 95)) |
            | items.get | \(getting.count) | \(Self.percentile(getting, 50)) | \(Self.percentile(getting, 95)) |

            """
        print(report)
        if let path = ProcessInfo.processInfo.environment["OP_LIVE_REPORT"] {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// The nearest-rank percentile, in milliseconds.
    private static func percentile(_ samples: [Duration], _ percent: Int) -> String {
        let sorted = samples.sorted()
        let rank = (percent * sorted.count + 99) / 100
        let value = sorted[max(rank, 1) - 1]
        let milliseconds = Double(value.components.seconds) * 1000 + Double(value.components.attoseconds) / 1e15
        return String(format: "%.0f ms", milliseconds)
    }
}

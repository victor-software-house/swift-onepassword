import Darwin
import Foundation
import Testing

@_spi(Benchmarks) @testable import OnePassword

/// The tests that use the core run one at a time. The cold open loads a WebAssembly module and
/// raises the process's memory, which would disturb the loop that watches it.
@Suite(.serialized)
struct ClientTests {
    @Test func malformedTokenIsAnAuthenticationError() async {
        let token = "malformed-token-sentinel"
        let error = await #expect(throws: OnePasswordError.self) {
            _ = try await Client(token: token, integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }

        #expect(error?.kind == .authentication)
        #expect(error?.message.contains(token) == false)
    }

    @Test func aHandleNoClientHoldsGivesATypedError() async {
        let client = Client(handle: 1 << 40)

        let vaults = await #expect(throws: OnePasswordError.self) { try await client.vaults() }
        let items = await #expect(throws: OnePasswordError.self) { try await client.items(vaultID: "v") }
        let item = await #expect(throws: OnePasswordError.self) { try await client.item(vaultID: "v", itemID: "i") }

        for error in [vaults, items, item] {
            #expect(error?.kind == .other)
            #expect(error?.message == "no client has this handle")
        }
    }

    @Test func aClosedHandleStaysATypedError() async {
        let handle: UInt64 = 1 << 41
        // The client closes its handle when it is freed. A second client on the same handle then
        // calls a handle that is closed, and closes it again.
        do { _ = Client(handle: handle) }

        for _ in 0..<2 {
            let client = Client(handle: handle)
            let error = await #expect(throws: OnePasswordError.self) { try await client.vaults() }
            #expect(error?.message == "no client has this handle")
        }
    }

    @Test func concurrentCallsOnOneClient() async {
        let client = Client(handle: 1 << 42)

        let answered = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    var count = 0
                    for _ in 0..<100 {
                        do throws(OnePasswordError) { _ = try await client.vaults() } catch { if error.kind == .other { count += 1 } }
                    }
                    return count
                }
            }
            return await group.reduce(0, +)
        }

        #expect(answered == 64 * 100)
    }

    /// An agent opens one client and keeps it for days, calling it every few minutes. A thousand
    /// calls on one client, and a thousand failing opens through the core, must leave the resident
    /// size where it was: a slow leak shows as growth.
    @Test func aLongLivedClientKeepsItsMemory() async {
        _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
        let client = Client(handle: 1 << 44)
        for _ in 0..<100 {
            _ = try? await client.vaults()
            _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }
        let start = residentMiB()

        for _ in 0..<1000 {
            _ = try? await client.vaults()
            _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }
        let end = residentMiB()

        print(String(format: "long-lived client, resident size: start %.1f MiB, end %.1f MiB", start, end))
        #expect(end - start < 32, "the resident size grew from \(start) to \(end) MiB")
    }

    /// Every reply the core returns is a C string that the client frees with op_free. The malloc
    /// zones hold C strings, and the Go heap lives apart from them, so a reply left allocated
    /// raises the bytes in use by its size on each call.
    @Test func repliesAreFreed() async {
        let client = Client(handle: 1 << 43)
        for _ in 0..<10_000 { _ = try? await client.vaults() }
        let before = mallocBytesInUse()

        for _ in 0..<100_000 { _ = try? await client.vaults() }
        let growth = Int64(mallocBytesInUse()) - Int64(before)

        // A reply that is never freed is 76 bytes in an 80-byte block: 8 MB over the loop. The
        // allocator itself settles within a megabyte.
        #expect(growth < 2 << 20, "the malloc zones grew by \(growth) bytes")
    }
}

private func residentMiB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

private func mallocBytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
}

import Darwin
import Foundation
import Testing

@_spi(Benchmarks) @testable import OnePassword

/// The tests that use the core run one at a time. The cold open loads a WebAssembly module and
/// raises the process's memory, which would disturb the loop that watches it.
@Suite(.serialized)
struct ClientTests {
    @Test func malformedTokenIsAnAuthenticationFailure() async {
        let token = "malformed-token-sentinel"
        let error = await #expect(throws: OnePasswordError.self) {
            _ = try await Client(token: token, integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }

        #expect(error?.code == .authenticationFailed)
        #expect(error?.message.contains(token) == false)
    }

    @Test func aHandleNoClientHasGivesATypedError() async {
        let client = Client(handle: 1 << 40)

        let vaults = await #expect(throws: OnePasswordError.self) { try await client.vaults() }
        let items = await #expect(throws: OnePasswordError.self) { try await client.items(inVault: "v") }
        let item = await #expect(throws: OnePasswordError.self) { try await client.item("i", inVault: "v") }

        for error in [vaults, items, item] {
            #expect(error?.code == .requestFailed)
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
                        do throws(OnePasswordError) { _ = try await client.vaults() } catch { if error.code == .requestFailed { count += 1 } }
                    }
                    return count
                }
            }
            return await group.reduce(0, +)
        }

        #expect(answered == 64 * 100)
    }

    /// An agent opens one client and keeps it for days, calling it every few minutes.
    /// In CI the core's memory grew once early in the loop, by up to 15 MiB, and then stayed.
    ///
    /// A leak grows with every call instead, so the test reads the growth over the last 500 calls.
    /// A leak of 2 KiB a call, client or failing open, grows that by 1 MiB.
    @Test func aLongLivedClientKeepsItsMemory() async {
        _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
        let client = Client(handle: 1 << 44)
        for _ in 0..<100 {
            _ = try? await client.vaults()
            _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }
        let start = residentMiB()

        // The size after each hundred calls shows whether a growth comes in one step or builds up.
        var steps: [Double] = []
        for call in 1...1000 {
            _ = try? await client.vaults()
            _ = try? await Client(token: "malformed-token", integrationName: "swift-onepassword-tests", integrationVersion: "0")
            if call % 100 == 0 { steps.append(residentMiB()) }
        }
        let end = residentMiB()

        print(String(format: "long-lived client, resident size: start %.1f MiB, end %.1f MiB", start, end))
        print("long-lived client, resident size per hundred calls: " + steps.map { String(format: "%.1f", $0) }.joined(separator: " "))
        let late = end - steps[4]
        #expect(late < 1, "the resident size grew by \(late) MiB over the last 500 calls")
    }

    /// Every response the core returns is a C string that the client frees with op_free.
    /// The malloc zones store C strings, and the Go heap lives apart from them.
    /// So each response left allocated adds its size to the bytes in use.
    @Test func responsesAreFreed() async {
        let client = Client(handle: 1 << 43)
        for _ in 0..<10_000 { _ = try? await client.vaults() }
        let before = mallocBytesInUse()

        for _ in 0..<100_000 { _ = try? await client.vaults() }
        let growth = Int64(mallocBytesInUse()) - Int64(before)

        // A response that is never freed is 76 bytes in an 80-byte block: 8 MB over the loop.
        // The allocator itself settles within a megabyte.
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

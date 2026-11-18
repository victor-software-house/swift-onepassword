import Benchmark
import Foundation

@_spi(Benchmarks) import OnePassword

// The same fixtures as the tests: replies shaped like the SDK's, with fake values.
private func fixture(_ name: String) -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // OnePasswordBenchmarks
        .deletingLastPathComponent()  // Benchmarks, the package's directory of targets
        .deletingLastPathComponent()  // Benchmarks, the package
        .deletingLastPathComponent()  // the repository
    let url = root.appending(path: "Tests/OnePasswordTests/Fixtures/\(name).json")
    guard let text = try? Data(contentsOf: url) else {
        fatalError("no fixture at \(url.path)")
    }
    return text
}

let benchmarks: @Sendable () -> Void = {
    // A benchmark name has no space.
    // `thresholds update` writes a file with each space turned into an underscore.
    // `thresholds check` reads it under the name as written.
    //
    // Each benchmark runs in a process of its own, so Client.init-cold is a true cold start.
    //
    // A threshold fails `thresholds check` when a metric's p90 rises past the committed value
    // by more than the threshold's percentage.
    //
    // Only metrics that do not depend on the machine have one.
    // One run on GitHub's shared runners can take twice as long as another.
    // So the wall clock is measured and printed without a threshold.
    //
    // The malloc counts are exact, so their limit is narrow.
    // The resident peak of a cold start moves by a quarter between runs, so its limit is wide.
    let memoryLimit = BenchmarkThresholds(relative: [.p90: 50.0])
    let countLimit = BenchmarkThresholds(relative: [.p90: 5.0])
    let leakLimit = BenchmarkThresholds(absolute: [.p90: 8192])

    Benchmark(
        "Client.init-cold",
        configuration: .init(
            metrics: [.wallClock, .peakMemoryResident],
            timeUnits: .milliseconds,
            warmupIterations: 0,
            maxDuration: .seconds(60),
            maxIterations: 1,
            thresholds: [.peakMemoryResident: memoryLimit]
        )
    ) { benchmark in
        let token = "malformed-token"
        do throws(OnePasswordError) {
            _ = try await Client(token: token, integrationName: "benchmarks", integrationVersion: "0")
        } catch {
            blackHole(error)
        }
    }

    Benchmark(
        "Client.call-round-trip",
        configuration: .init(
            metrics: [.wallClock, .mallocCountTotal, .memoryLeakedBytes],
            timeUnits: .microseconds,
            scalingFactor: .kilo,
            thresholds: [
                .mallocCountTotal: countLimit,
                // A response left allocated is about 80 bytes a call, 80000 over the 1000 iterations.
                .memoryLeakedBytes: leakLimit,
            ]
        )
    ) { benchmark in
        // No client has this handle, so the core answers at once, without 1Password.
        let client = Client(handle: 1 << 40)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            do throws(OnePasswordError) {
                blackHole(try await client.vaults())
            } catch {
                blackHole(error)
            }
        }
        benchmark.stopMeasurement()
    }

    // What the call above spends before and after the core: a hop to another queue and back.
    Benchmark(
        "Reference-queue-hop",
        configuration: .init(
            metrics: [.wallClock, .mallocCountTotal],
            timeUnits: .microseconds,
            scalingFactor: .kilo,
            thresholds: [.mallocCountTotal: countLimit]
        )
    ) { benchmark in
        let queue = DispatchQueue(label: "reference", attributes: .concurrent)
        for _ in benchmark.scaledIterations {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume() }
            }
        }
    }

    let vaults = fixture("vault-list")
    Benchmark(
        "Decode-vault-list",
        configuration: .init(
            metrics: [.wallClock, .mallocCountTotal],
            timeUnits: .microseconds,
            scalingFactor: .kilo,
            thresholds: [.mallocCountTotal: countLimit]
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? BenchmarkSupport.decodeVaults(vaults))
        }
    }

    let items = fixture("item-list")
    Benchmark(
        "Decode-item-list",
        configuration: .init(
            metrics: [.wallClock, .mallocCountTotal],
            timeUnits: .microseconds,
            scalingFactor: .kilo,
            thresholds: [.mallocCountTotal: countLimit]
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? BenchmarkSupport.decodeItems(items))
        }
    }

    let sshKey = fixture("item-ssh-key")
    Benchmark(
        "Decode-ssh-key-item",
        configuration: .init(
            metrics: [.wallClock, .mallocCountTotal],
            timeUnits: .microseconds,
            scalingFactor: .kilo,
            thresholds: [.mallocCountTotal: countLimit]
        )
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? BenchmarkSupport.decodeItem(sshKey))
        }
    }
}

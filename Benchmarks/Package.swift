// swift-tools-version: 6.4
import PackageDescription

// A package of its own, so that the library gains no dependency on the benchmark package.
// Run it with `mise run bench:swift`.
let package = Package(
    name: "swift-onepassword-benchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ordo-one/benchmark.git", exact: "1.38.2"),
    ],
    targets: [
        .executableTarget(
            name: "OnePasswordBenchmarks",
            dependencies: [
                .product(name: "OnePassword", package: "swift-onepassword"),
                .product(name: "Benchmark", package: "benchmark"),
            ],
            // The benchmark plugin takes an executable target whose directory sits in one named Benchmarks.
            path: "Benchmarks/OnePasswordBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        ),
    ]
)

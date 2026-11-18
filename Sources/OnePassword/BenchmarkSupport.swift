import Foundation

/// Entry points for Benchmarks/, which times the decoding that the public API hides.
@_spi(Benchmarks)
public enum BenchmarkSupport {
    public static func decodeVaults(_ json: Data) throws(OnePasswordError) -> [VaultOverview] {
        try CoreJSON.decode(CoreResponse<[VaultOverview]>.self, from: json).result ?? []
    }

    public static func decodeItems(_ json: Data) throws(OnePasswordError) -> [ItemOverview] {
        try CoreJSON.decode(CoreResponse<[ItemOverview]>.self, from: json).result ?? []
    }

    public static func decodeItem(_ json: Data) throws(OnePasswordError) -> Item? {
        try CoreJSON.decode(CoreResponse<Item>.self, from: json).result
    }
}

import Foundation

/// Entry points for Benchmarks/, which times the decoding that the public API hides.
@_spi(Benchmarks)
public enum BenchmarkSupport {
    public static func decodeVaults(_ json: Data) throws(OnePasswordError) -> [VaultOverview] {
        try Wire.decode(Wire.Reply<[VaultOverview]>.self, from: json).result ?? []
    }

    public static func decodeItems(_ json: Data) throws(OnePasswordError) -> [ItemOverview] {
        try Wire.decode(Wire.Reply<[ItemOverview]>.self, from: json).result ?? []
    }

    public static func decodeItem(_ json: Data) throws(OnePasswordError) -> Item? {
        try Wire.decode(Wire.Reply<Item>.self, from: json).result
    }
}

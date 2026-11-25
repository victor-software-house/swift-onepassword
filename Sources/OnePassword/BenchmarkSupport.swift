import Foundation

/// Entry points for Benchmarks/, which times the decoding that the public API hides.
@_spi(Benchmarks)
public enum BenchmarkSupport {
    /// Decodes the core's response to a vault list, as `Client.vaults()` does.
    public static func decodeVaults(_ json: Data) throws(OnePasswordError) -> [VaultOverview] {
        try CoreJSON.decode(CoreResponse<[VaultOverview]>.self, from: json).result ?? []
    }

    /// Decodes the core's response to an item list, as `Client.items(inVault:)` does.
    public static func decodeItems(_ json: Data) throws(OnePasswordError) -> [ItemOverview] {
        try CoreJSON.decode(CoreResponse<[ItemOverview]>.self, from: json).result ?? []
    }

    /// Decodes the core's response to one item, as `Client.item(_:inVault:)` does.
    /// It returns nil when the response has no result.
    public static func decodeItem(_ json: Data) throws(OnePasswordError) -> Item? {
        try CoreJSON.decode(CoreResponse<Item>.self, from: json).result
    }
}

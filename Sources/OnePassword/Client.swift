import COnePassword
import Dispatch
import Foundation

/// A 1Password client for one service account token.
/// Calls run on a dedicated queue, because each blocks until the SDK answers and so cannot run on
/// Swift's cooperative pool.
public final class Client: Sendable {
    private static let queue = DispatchQueue(label: "swift-onepassword.calls", attributes: .concurrent)

    private let handle: UInt64

    /// Opens a client for a service account token.
    /// `integrationName` and `integrationVersion` name the calling program to 1Password.
    /// It throws when the core cannot open the client, for example for a malformed token.
    public init(token: String, integrationName: String, integrationVersion: String) async throws(OnePasswordError) {
        let json = try await Self.run {
            token.withCString { token in
                integrationName.withCString { name in
                    integrationVersion.withCString { version in
                        Self.take(op_client_open(Self.mutable(token), Self.mutable(name), Self.mutable(version)))
                    }
                }
            }
        }
        let response = try CoreJSON.decode(CoreResponse<Never>.self, from: json)
        if let error = response.error { throw error.onePasswordError }
        guard let handle = response.handle else {
            throw OnePasswordError(code: .requestFailed, message: "the client did not return a handle")
        }
        self.handle = handle
    }

    /// A client for a handle the core already has.
    /// Tests and benchmarks use a handle that no client has to run calls that fail before they reach
    /// 1Password, with no token.
    @_spi(Benchmarks) public init(handle: UInt64) {
        self.handle = handle
    }

    deinit {
        op_client_close(handle)
    }

    /// The vaults the token reads, with their content versions.
    public func vaults() async throws(OnePasswordError) -> [VaultOverview] {
        try await call(CoreRequest(method: .listVaults), as: [VaultOverview].self) ?? []
    }

    /// The items of a vault, as overviews.
    public func items(inVault vaultID: String) async throws(OnePasswordError) -> [ItemOverview] {
        try await call(CoreRequest(method: .listItems, vaultID: vaultID), as: [ItemOverview].self) ?? []
    }

    /// One item with its fields.
    public func item(_ itemID: String, inVault vaultID: String) async throws(OnePasswordError) -> Item {
        let item = try await call(
            CoreRequest(method: .getItem, vaultID: vaultID, itemID: itemID), as: Item.self
        )
        guard let item else { throw OnePasswordError(code: .requestFailed, message: "the item is empty") }
        return item
    }

    /// Creates items in one vault, in one call.
    /// The results are in the order of `items`, so one rejected item does not hide the others.
    public func create(
        _ items: [ItemContent], inVault vaultID: String
    ) async throws(OnePasswordError) -> [ItemResult] {
        try await call(CoreRequest(method: .createItems, vaultID: vaultID, items: items), as: [ItemResult].self) ?? []
    }

    /// Reads items of one vault by their IDs, in one call.
    /// The results are in the order of `itemIDs`, so one missing item does not hide the others.
    public func items(
        _ itemIDs: [String], inVault vaultID: String
    ) async throws(OnePasswordError) -> [ItemResult] {
        try await call(CoreRequest(method: .getItems, vaultID: vaultID, itemIDs: itemIDs), as: [ItemResult].self) ?? []
    }

    /// Sets the title, fields, sections, notes and tags of an item, and returns the updated item.
    /// The item keeps its category, websites, files and document.
    /// The call fails when another writer changes the item between its read and its write.
    public func update(
        _ itemID: String, inVault vaultID: String, to content: ItemContent
    ) async throws(OnePasswordError) -> Item {
        let item = try await call(
            CoreRequest(method: .updateItem, vaultID: vaultID, itemID: itemID, content: content), as: Item.self
        )
        guard let item else { throw OnePasswordError(code: .requestFailed, message: "the item is empty") }
        return item
    }

    /// Deletes items of one vault, in one call, and returns the failure of each item it could not delete.
    /// The result is empty when every item was deleted.
    public func delete(
        _ itemIDs: [String], inVault vaultID: String
    ) async throws(OnePasswordError) -> [String: ItemFailure] {
        let request = CoreRequest(method: .deleteItems, vaultID: vaultID, itemIDs: itemIDs)
        return try await call(request, as: [String: ItemFailure].self) ?? [:]
    }

    /// Moves an item to the archive.
    public func archive(_ itemID: String, inVault vaultID: String) async throws(OnePasswordError) {
        _ = try await call(CoreRequest(method: .archiveItem, vaultID: vaultID, itemID: itemID), as: Never.self)
    }

    private func call<Value: Decodable & Sendable>(
        _ request: CoreRequest, as type: Value.Type
    ) async throws(OnePasswordError) -> Value? {
        let handle = handle
        let body = CoreJSON.encode(request)
        let json = try await Self.run {
            body.withCString { body in
                Self.take(op_call(handle, Self.mutable(body)))
            }
        }
        let response = try CoreJSON.decode(CoreResponse<Value>.self, from: json)
        if let error = response.error { throw error.onePasswordError }
        return response.result
    }

    /// Runs a blocking C call on the dedicated queue.
    /// A nil result means the core returned no response.
    private static func run(_ work: @escaping @Sendable () -> Data?) async throws(OnePasswordError) -> Data {
        let json = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
        guard let json else { throw OnePasswordError(code: .requestFailed, message: "the core returned no response") }
        return json
    }

    /// The generated header declares its string parameters without const.
    private static func mutable(_ pointer: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
        UnsafeMutablePointer(mutating: pointer)
    }

    /// Copies a response once, into the bytes the JSON decoder reads, and frees it.
    private static func take(_ response: UnsafeMutablePointer<CChar>?) -> Data? {
        guard let response else { return nil }
        defer { op_free(response) }
        return Data(bytes: response, count: strlen(response))
    }
}

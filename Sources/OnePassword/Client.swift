import COnePassword
import Dispatch
import Foundation

/// A 1Password client for one service account token. Calls run on a dedicated queue, because
/// each blocks until the SDK's answer arrives and so cannot run on Swift's cooperative pool.
public final class Client: Sendable {
    private static let queue = DispatchQueue(label: "swift-onepassword.calls", attributes: .concurrent)

    private let handle: UInt64

    public init(token: String, integrationName: String, integrationVersion: String) async throws(OnePasswordError) {
        let json = await Self.run {
            token.withCString { token in
                integrationName.withCString { name in
                    integrationVersion.withCString { version in
                        Self.take(op_client_open(Self.mutable(token), Self.mutable(name), Self.mutable(version)))
                    }
                }
            }
        }
        let reply = try Wire.decode(Wire.Reply<Never>.self, from: json)
        if let error = reply.error { throw error.error }
        guard let handle = reply.handle else {
            throw OnePasswordError(kind: .other, message: "the client did not return a handle")
        }
        self.handle = handle
    }

    deinit {
        op_client_close(handle)
    }

    /// The vaults the token reads, with their content versions.
    public func vaults() async throws(OnePasswordError) -> [VaultOverview] {
        try await call(Wire.Request(method: "vaults.list"), as: [VaultOverview].self) ?? []
    }

    /// The items of a vault, as overviews.
    public func items(vaultID: String) async throws(OnePasswordError) -> [ItemOverview] {
        try await call(Wire.Request(method: "items.list", vaultId: vaultID), as: [ItemOverview].self) ?? []
    }

    /// One item with its fields.
    public func item(vaultID: String, itemID: String) async throws(OnePasswordError) -> Item {
        let item = try await call(
            Wire.Request(method: "items.get", vaultId: vaultID, itemId: itemID), as: Item.self
        )
        guard let item else { throw OnePasswordError(kind: .other, message: "the item is empty") }
        return item
    }

    private func call<Value: Decodable & Sendable>(
        _ request: Wire.Request, as type: Value.Type
    ) async throws(OnePasswordError) -> Value? {
        let handle = handle
        let body = Wire.encode(request)
        let json = await Self.run {
            body.withCString { body in
                Self.take(op_call(handle, Self.mutable(body)))
            }
        }
        let reply = try Wire.decode(Wire.Reply<Value>.self, from: json)
        if let error = reply.error { throw error.error }
        return reply.result
    }

    /// Runs a blocking C call on the dedicated queue.
    private static func run(_ work: @escaping @Sendable () -> String) async -> String {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// The generated header declares its string parameters without const.
    private static func mutable(_ pointer: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
        UnsafeMutablePointer(mutating: pointer)
    }

    /// Copies a reply into a Swift string and frees it.
    private static func take(_ reply: UnsafeMutablePointer<CChar>?) -> String {
        guard let reply else { return #"{"error":{"kind":"other","message":"the core returned no reply"}}"# }
        defer { op_free(reply) }
        return String(cString: reply)
    }
}

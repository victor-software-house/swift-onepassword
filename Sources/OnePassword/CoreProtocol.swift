import Foundation

/// The JSON that the C interface of core/ reads and writes.
enum CoreMethod: String, Encodable {
    case listVaults = "vaults.list"
    case listItems = "items.list"
    case getItem = "items.get"
    case createItems = "items.createAll"
    case getItems = "items.getAll"
    case updateItem = "items.update"
    case deleteItems = "items.deleteAll"
    case archiveItem = "items.archive"
}

struct CoreRequest: Encodable {
    let method: CoreMethod
    var vaultID: String?
    var itemID: String?
    var items: [ItemContent]?
    var itemIDs: [String]?
    var content: ItemContent?

    private enum CodingKeys: String, CodingKey {
        case method, items, content
        case vaultID = "vaultId"
        case itemID = "itemId"
        case itemIDs = "itemIds"
    }
}

struct CoreResponse<Result: Decodable>: Decodable {
    let handle: UInt64?
    let result: Result?
    let error: CoreError?
}

struct CoreError: Decodable {
    let code: String
    let message: String

    /// An unknown code becomes `requestFailed`, and so do the core's `unknownClient` and
    /// `invalidRequest`.
    var onePasswordError: OnePasswordError {
        OnePasswordError(code: OnePasswordError.Code(rawValue: code) ?? .requestFailed, message: message)
    }
}

enum CoreJSON {
    static func decode<Value: Decodable>(_ type: Value.Type, from json: Data) throws(OnePasswordError) -> Value {
        do {
            return try decoder.decode(type, from: json)
        } catch {
            throw OnePasswordError(code: .invalidResponse, message: "the response could not be decoded")
        }
    }

    static func encode(_ request: CoreRequest) -> String {
        // A request has only strings, and lists and structs of them, so encoding cannot fail.
        let data = (try? encoder.encode(request)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // Foundation's coders are Sendable and safe to share.
    // Building one per call costs more than a call that fails at once.
    private static let encoder = JSONEncoder()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = RFC3339.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "not an RFC 3339 timestamp")
                )
            }
            return date
        }
        return decoder
    }()
}

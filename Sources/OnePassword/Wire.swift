import Foundation

/// The JSON the C interface of core/ speaks.
enum Wire {
    struct Failure: Decodable {
        let kind: String
        let message: String

        var error: OnePasswordError {
            OnePasswordError(kind: OnePasswordError.Kind(rawValue: kind) ?? .other, message: message)
        }
    }

    struct Reply<Payload: Decodable>: Decodable {
        let handle: UInt64?
        let result: Payload?
        let error: Failure?
    }

    struct Request: Encodable {
        let method: String
        var vaultId: String?
        var itemId: String?
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws(OnePasswordError) -> Value {
        do {
            return try decoder.decode(type, from: Data(json.utf8))
        } catch {
            throw OnePasswordError(kind: .other, message: "the reply could not be decoded")
        }
    }

    static func encode(_ request: Request) -> String {
        // A request holds only strings, so encoding cannot fail.
        let data = (try? JSONEncoder().encode(request)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "not an RFC 3339 timestamp")
                )
            }
            return date
        }
        return decoder
    }

    /// Reads Go's time.Time encoding: RFC 3339 with an optional fraction of up to nine digits,
    /// and `Z` or an offset.
    static func parseTimestamp(_ text: String) -> Date? {
        var whole = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
            fraction = value
            whole = String(text[..<dot]) + text[digits.endIndex...]
        }
        let style = Date.ISO8601FormatStyle().timeZoneSeparator(.colon)
        guard let date = try? Date(whole, strategy: style) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}

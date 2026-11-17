/// A failure of a 1Password call. It never holds the service account token.
public struct OnePasswordError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        /// The token was refused, or the client could not start.
        case authentication
        /// 1Password's rate limit answered; the message carries no retry time.
        case rateLimited
        case other
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { "\(kind.rawValue): \(message)" }
}

/// A failure of a 1Password call. It never holds the service account token.
public struct OnePasswordError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        /// 1Password refused the token or did not authenticate the request, for example a token that
        /// is malformed, rotated or revoked.
        case authentication
        /// 1Password's rate limit answered; the message carries no retry time.
        case rateLimited
        /// The call succeeded, but its reply does not read as the type the call returns.
        case decoding
        /// Any other failure, such as no network, a timeout or a vault the token cannot read.
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

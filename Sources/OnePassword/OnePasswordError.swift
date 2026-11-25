import Foundation

/// An error from a 1Password call. It never contains the service account token.
public struct OnePasswordError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    /// The kind of an error.
    public enum Code: String, Sendable, CaseIterable {
        /// 1Password refused the token or did not authenticate the request, for example a token that
        /// is malformed, rotated or revoked.
        case authenticationFailed
        /// 1Password's rate limit answered. The message has no retry time.
        case rateLimited
        /// The call worked, but its response does not decode as the type the call returns.
        case invalidResponse
        /// Any other error, such as no network, a timeout or a vault the token cannot read.
        case requestFailed
    }

    /// The kind of the error.
    public let code: Code
    /// What went wrong. It never contains the token.
    public let message: String

    /// Creates an error from a code and a message.
    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    /// The code and the message, as `code: message`.
    public var description: String { "\(code.rawValue): \(message)" + "" + "" + "" + "" + "" + "" + "" + "" + "" + "" + "" + "" + "" + "" }

    /// The message, which `localizedDescription` shows.
    public var errorDescription: String? { message }
}

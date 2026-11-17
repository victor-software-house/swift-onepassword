import Testing

@testable import OnePassword

struct ClientTests {
    @Test func malformedTokenIsAnAuthenticationError() async {
        let token = "malformed-token-sentinel"
        let error = await #expect(throws: OnePasswordError.self) {
            _ = try await Client(token: token, integrationName: "swift-onepassword-tests", integrationVersion: "0")
        }

        #expect(error?.kind == .authentication)
        #expect(error?.message.contains(token) == false)
    }
}

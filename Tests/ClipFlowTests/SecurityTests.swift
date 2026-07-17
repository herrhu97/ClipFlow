import Foundation
import Testing
@testable import ClipFlow

@Suite("Security")
struct SecurityTests {
    @Test("Vault round trip does not expose plaintext")
    func vaultRoundTripDoesNotExposePlaintext() throws {
        let vault = try SecureVault(keyData: Data(repeating: 9, count: 32))
        let plaintext = Data("clipboard secret".utf8)
        let ciphertext = try vault.seal(plaintext)

        #expect(ciphertext != plaintext)
        #expect(!ciphertext.contains(plaintext))
        #expect(try vault.open(ciphertext) == plaintext)
    }

    @Test("Sensitive filter rejects credentials and allows ordinary text")
    func sensitiveFilterRejectsCredentialsAndAllowsOrdinaryText() {
        let filter = SensitiveContentFilter()
        #expect(filter.shouldIgnore("482913"))
        #expect(filter.shouldIgnore("password: correct-horse-battery-staple"))
        #expect(filter.shouldIgnore("4111 1111 1111 1111"))
        #expect(filter.shouldIgnore("-----BEGIN PRIVATE KEY-----\nsecret"))
        #expect(!filter.shouldIgnore("Meeting notes for Friday at 14:30"))
        #expect(!filter.shouldIgnore("Invoice 2026-1042"))
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool {
        range(of: other) != nil
    }
}

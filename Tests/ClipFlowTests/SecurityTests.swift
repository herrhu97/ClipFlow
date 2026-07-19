import Foundation
import Testing
@testable import ClipFlow

@Suite("Security")
struct SecurityTests {
    @Test("Default key file lives in the user home directory")
    func defaultKeyFileLocation() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clipflow.json", isDirectory: false)
        #expect(SecureVault.defaultKeyFileURL == expected)
    }

    @Test("File-backed key persists with owner-only permissions")
    func fileBackedKeyPersists() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appendingPathComponent(".clipflow.json")

        let first = try SecureVault(keyFileURL: keyFile)
        let plaintext = Data("persistent file key".utf8)
        let ciphertext = try first.seal(plaintext)

        #expect(FileManager.default.fileExists(atPath: keyFile.path))
        #expect(try keyFilePermissions(keyFile) == 0o600)

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: keyFile)) as? [String: Any]
        )
        #expect(object["version"] as? Int == 1)
        let encodedKey = try #require(object["database_key"] as? String)
        #expect(Data(base64Encoded: encodedKey)?.count == 32)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: keyFile.path)
        let reopened = try SecureVault(keyFileURL: keyFile)
        #expect(try reopened.open(ciphertext) == plaintext)
        #expect(try keyFilePermissions(keyFile) == 0o600)
    }

    @Test("Invalid key file fails without falling back")
    func invalidKeyFileFailsClosed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appendingPathComponent(".clipflow.json")
        let invalid = Data("{\"version\":1,\"database_key\":\"not-base64\"}".utf8)
        try invalid.write(to: keyFile)

        do {
            _ = try SecureVault(keyFileURL: keyFile)
            Issue.record("Expected the invalid key file to stop startup.")
        } catch SecureVaultError.invalidKeyFile {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: keyFile) == invalid)
    }

    @Test("Existing history requires an existing encryption key")
    func existingHistoryRequiresKey() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appendingPathComponent(".clipflow.json")

        do {
            _ = try SecureVault(keyFileURL: keyFile, requiresExistingKey: true)
            Issue.record("Expected a missing key error.")
        } catch SecureVaultError.missingKeyFile(let path) {
            #expect(path == keyFile.path)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: keyFile.path))
    }

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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipFlowSecurityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func keyFilePermissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue) & 0o777
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool {
        range(of: other) != nil
    }
}

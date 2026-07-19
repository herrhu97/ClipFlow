import CryptoKit
import Foundation

enum SecureVaultError: LocalizedError {
    case keyFile(String)
    case invalidKey
    case invalidKeyFile
    case missingKeyFile(String)
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .keyFile(let message):
            return "The encryption key file could not be accessed: \(message)"
        case .invalidKey:
            return "The encryption key is invalid."
        case .invalidKeyFile:
            return "The encryption key file is invalid."
        case .missingKeyFile(let path):
            return "The encryption key file is missing at \(path). Restore it to open the existing history."
        case .invalidCiphertext:
            return "The encrypted clipboard data is invalid."
        }
    }
}

final class SecureVault {
    static var defaultKeyFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clipflow.json", isDirectory: false)
    }

    private static let keyFileVersion = 1

    private struct KeyFileRecord: Codable {
        let version: Int
        let databaseKey: String
    }

    private let key: SymmetricKey

    init(
        keyFileURL: URL = SecureVault.defaultKeyFileURL,
        requiresExistingKey: Bool = false
    ) throws {
        if FileManager.default.fileExists(atPath: keyFileURL.path) {
            key = SymmetricKey(data: try Self.readKeyFile(at: keyFileURL))
            return
        }

        guard !requiresExistingKey else {
            throw SecureVaultError.missingKeyFile(keyFileURL.path)
        }

        let newKey = SymmetricKey(size: .bits256)
        let data = newKey.withUnsafeBytes { Data($0) }
        try Self.writeKeyFile(data, to: keyFileURL)
        key = newKey
    }

    init(keyData: Data) throws {
        guard keyData.count == 32 else { throw SecureVaultError.invalidKey }
        key = SymmetricKey(data: keyData)
    }

    func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw SecureVaultError.invalidCiphertext }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private static func readKeyFile(at url: URL) throws -> Data {
        let encoded: Data
        do {
            encoded = try Data(contentsOf: url)
        } catch {
            throw SecureVaultError.keyFile(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let record = try? decoder.decode(KeyFileRecord.self, from: encoded),
              record.version == keyFileVersion,
              let keyData = Data(base64Encoded: record.databaseKey),
              keyData.count == 32 else {
            throw SecureVaultError.invalidKeyFile
        }

        try setOwnerOnlyPermissions(on: url)
        return keyData
    }

    private static func writeKeyFile(_ keyData: Data, to url: URL) throws {
        guard keyData.count == 32 else { throw SecureVaultError.invalidKey }
        let record = KeyFileRecord(
            version: keyFileVersion,
            databaseKey: keyData.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var encoded: Data
        do {
            encoded = try encoder.encode(record)
            encoded.append(0x0A)
        } catch {
            throw SecureVaultError.keyFile(error.localizedDescription)
        }

        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            guard fileManager.createFile(
                atPath: temporaryURL.path,
                contents: encoded,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw SecureVaultError.keyFile("Unable to create \(temporaryURL.lastPathComponent).")
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
            try setOwnerOnlyPermissions(on: url)
        } catch let error as SecureVaultError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw SecureVaultError.keyFile(error.localizedDescription)
        }
    }

    private static func setOwnerOnlyPermissions(on url: URL) throws {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw SecureVaultError.keyFile(error.localizedDescription)
        }
    }
}

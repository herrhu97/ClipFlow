import CryptoKit
import Foundation
import Testing
@testable import ClipFlow

@Suite("ClipStore", .serialized)
@MainActor
struct ClipStoreTests {
    @Test("Encrypted content persists across restart")
    func encryptedContentPersistsAcrossStoreRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 7, count: 32)
        var firstStore: ClipStore? = try ClipStore(
            rootDirectory: directory,
            vault: SecureVault(keyData: key)
        )
        let secret = "a private clipboard sentence"
        _ = try firstStore?.add(capture(secret), duplicateHandling: .moveToTop)
        #expect(firstStore?.items.first?.textContent == secret)
        firstStore = nil

        let reopened = try ClipStore(
            rootDirectory: directory,
            vault: SecureVault(keyData: key)
        )
        #expect(reopened.items.count == 1)
        #expect(reopened.items.first?.textContent == secret)

        let databaseBytes = try Data(contentsOf: directory.appendingPathComponent("history.sqlite"))
        #expect(String(data: databaseBytes, encoding: .utf8)?.range(of: secret) == nil)
    }

    @Test("Duplicate moves the existing item to the top")
    func duplicateMovesExistingItemToTop() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try store.add(capture("first"), duplicateHandling: .moveToTop)
        _ = try store.add(capture("second"), duplicateHandling: .moveToTop)
        _ = try store.add(capture("first"), duplicateHandling: .moveToTop)

        #expect(store.items.count == 2)
        #expect(store.items.first?.textContent == "first")
    }

    @Test("Keep both permits duplicates")
    func keepBothAllowsDuplicateRecords() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try store.add(capture("same"), duplicateHandling: .keepBoth)
        _ = try store.add(capture("same"), duplicateHandling: .keepBoth)
        #expect(store.items.count == 2)
    }

    @Test("Pinned clips survive storage cleanup")
    func pinnedItemsSurviveStorageCleanup() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pinnedResult = try store.add(capture("keep me"), duplicateHandling: .moveToTop)
        let pinned = try #require(pinnedResult)
        _ = try store.add(capture("remove me"), duplicateHandling: .moveToTop)
        try store.setPinned(pinned, pinned: true)

        try store.performCleanup(retention: .forever, maximumStorageMB: 0)
        #expect(store.items.map(\.textContent) == ["keep me"])
        #expect(store.items[0].isPinned)
    }

    @Test("Deleting a group keeps its clips")
    func deletingCollectionKeepsItsClipboardItems() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let itemResult = try store.add(capture("grouped"), duplicateHandling: .moveToTop)
        let item = try #require(itemResult)
        let collection = try store.createCollection(named: "Work")
        try store.move(item, to: collection)
        #expect(store.items.first?.collectionID == collection.id)

        try store.deleteCollection(collection)
        #expect(store.items.count == 1)
        #expect(store.items.first?.collectionID == nil)
    }

    @Test("Clear history removes encrypted external payloads")
    func clearHistoryRemovesExternalPayloadFiles() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageLikeData = Data(repeating: 42, count: 700_000)
        let captured = CapturedContent(
            type: .image,
            data: imageLikeData,
            displayText: nil,
            searchText: "image",
            contentHash: "image-hash",
            sourceAppIdentifier: nil,
            sourceAppName: "Tests"
        )
        let itemResult = try store.add(captured, duplicateHandling: .moveToTop)
        let item = try #require(itemResult)
        let path = try #require(item.payloadPath)
        #expect(FileManager.default.fileExists(atPath: path))

        try store.clearHistory()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(store.items.isEmpty)
    }

    @Test("Store accepts 1,000 mixed clipboard records")
    func storesOneThousandMixedRecords() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let types: [ClipboardContentType] = [.text, .richText, .url, .image, .file, .html]

        for index in 0..<1_000 {
            let type = types[index % types.count]
            let value = "record-\(index)-\(type.rawValue)"
            let data = Data(value.utf8)
            let captured = CapturedContent(
                type: type,
                data: data,
                displayText: type == .image ? nil : value,
                searchText: value,
                contentHash: "mixed-\(index)",
                sourceAppIdentifier: "com.clipflow.tests",
                sourceAppName: "Tests"
            )
            _ = try store.add(captured, duplicateHandling: .keepBoth)
        }

        #expect(store.items.count == 1_000)
        #expect(Set(store.items.map(\.type)) == Set(types))
    }

    private func makeStore() throws -> (ClipStore, URL) {
        let directory = temporaryDirectory()
        return (
            try ClipStore(
                rootDirectory: directory,
                vault: SecureVault(keyData: Data(repeating: 3, count: 32))
            ),
            directory
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipFlowTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func capture(_ text: String) -> CapturedContent {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CapturedContent(
            type: .text,
            data: data,
            displayText: text,
            searchText: "\(text) Tests",
            contentHash: hash,
            sourceAppIdentifier: "com.clipflow.tests",
            sourceAppName: "Tests"
        )
    }
}

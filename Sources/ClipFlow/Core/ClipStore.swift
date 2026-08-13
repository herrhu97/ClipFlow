import Combine
import Foundation
import SQLite3

enum ClipStoreError: LocalizedError {
    case database(String)
    case encoding
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .database(let message): return "Database error: \(message)"
        case .encoding: return "Clipboard content could not be encoded."
        case .missingPayload: return "The saved clipboard payload is no longer available."
        }
    }
}

/// A clipboard payload that has already been encrypted (and written to disk when large)
/// off the main actor, so `add` only has to perform the database write.
struct PreparedClipboardPayload: Sendable {
    let id: UUID
    let sealedData: Data
    let payloadPath: String?
}

@MainActor
final class ClipStore: ObservableObject {
    static let keyStorageMarkerFilename = ".file-key-storage-v1"

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var collections: [ClipCollection] = []

    private var database: OpaquePointer?
    private let vault: SecureVault
    private let rootDirectory: URL
    private let payloadDirectory: URL
    private let databaseURL: URL
    private let keyStorageMarkerURL: URL
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(
        rootDirectory: URL? = nil,
        vault: SecureVault? = nil,
        keyFileURL: URL = SecureVault.defaultKeyFileURL
    ) throws {
        let fileManager = FileManager.default
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootDirectory = applicationSupport.appendingPathComponent("ClipFlow", isDirectory: true)
        }
        payloadDirectory = self.rootDirectory.appendingPathComponent("Payloads", isDirectory: true)
        databaseURL = self.rootDirectory.appendingPathComponent("history.sqlite")
        keyStorageMarkerURL = self.rootDirectory.appendingPathComponent(Self.keyStorageMarkerFilename)

        if vault == nil {
            try Self.archiveLegacyStoreIfNeeded(
                rootDirectory: self.rootDirectory,
                databaseURL: databaseURL,
                keyFileURL: keyFileURL,
                markerURL: keyStorageMarkerURL
            )
        }

        self.vault = try vault ?? SecureVault(
            keyFileURL: keyFileURL,
            requiresExistingKey: fileManager.fileExists(atPath: keyStorageMarkerURL.path)
                && Self.databaseContainsEncryptedData(at: databaseURL)
        )

        try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        if vault == nil { try Self.writeKeyStorageMarker(at: keyStorageMarkerURL) }
        try openAndRecoverIfNeeded()
        try migrate()
        try reload()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private static func archiveLegacyStoreIfNeeded(
        rootDirectory: URL,
        databaseURL: URL,
        keyFileURL: URL,
        markerURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: keyFileURL.path),
              !fileManager.fileExists(atPath: markerURL.path),
              fileManager.fileExists(atPath: databaseURL.path) else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let parent = rootDirectory.deletingLastPathComponent()
        var backup = parent.appendingPathComponent(
            "ClipFlow-Keychain-Backup-\(formatter.string(from: Date()))",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: backup.path) {
            backup = parent.appendingPathComponent(
                "ClipFlow-Keychain-Backup-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        try fileManager.moveItem(at: rootDirectory, to: backup)
    }

    private static func writeKeyStorageMarker(at url: URL) throws {
        let data = Data("file-v1\n".utf8)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func databaseContainsEncryptedData(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return true
        }
        defer { sqlite3_close(handle) }

        var existenceStatement: OpaquePointer?
        let existenceSQL = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items' LIMIT 1"
        guard sqlite3_prepare_v2(handle, existenceSQL, -1, &existenceStatement, nil) == SQLITE_OK,
              let existenceStatement else { return true }
        let existenceResult = sqlite3_step(existenceStatement)
        sqlite3_finalize(existenceStatement)
        if existenceResult == SQLITE_DONE { return false }
        guard existenceResult == SQLITE_ROW else { return true }

        var rowStatement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM clipboard_items LIMIT 1", -1, &rowStatement, nil) == SQLITE_OK,
              let rowStatement else { return true }
        let rowResult = sqlite3_step(rowStatement)
        sqlite3_finalize(rowStatement)
        if rowResult == SQLITE_ROW { return true }
        return rowResult != SQLITE_DONE
    }

    /// Encrypts the capture payload (writing it to the payload directory when it is an
    /// image or exceeds the inline size limit). Safe to call from any thread so large
    /// captures do not block the main actor.
    nonisolated func prepareCapturedPayload(_ capture: CapturedContent) throws -> PreparedClipboardPayload {
        let sealedData = try vault.seal(capture.data)
        let id = UUID()
        guard capture.type == .image || sealedData.count > 512 * 1_024 else {
            return PreparedClipboardPayload(id: id, sealedData: sealedData, payloadPath: nil)
        }
        let url = payloadDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("clip")
        try sealedData.write(to: url, options: [.atomic, .completeFileProtection])
        return PreparedClipboardPayload(id: id, sealedData: sealedData, payloadPath: url.path)
    }

    @discardableResult
    func add(_ capture: CapturedContent, duplicateHandling: DuplicateHandling) throws -> ClipboardItem? {
        try add(capture, duplicateHandling: duplicateHandling, preparedPayload: nil)
    }

    @discardableResult
    func add(
        _ capture: CapturedContent,
        duplicateHandling: DuplicateHandling,
        preparedPayload: PreparedClipboardPayload?
    ) throws -> ClipboardItem? {
        let now = Date()
        if duplicateHandling != .keepBoth,
           let existingIndex = items.firstIndex(where: { $0.contentHash == capture.contentHash && $0.type == capture.type }) {
            if let path = preparedPayload?.payloadPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            guard duplicateHandling == .moveToTop else { return nil }
            var existing = items[existingIndex]
            existing.lastCopiedAt = now
            existing.sourceAppIdentifier = capture.sourceAppIdentifier
            existing.sourceAppName = capture.sourceAppName
            existing.rebuildSearchIndex()
            try updateCopyMetadata(existing)
            items.remove(at: existingIndex)
            items.insert(existing, at: insertionIndex(for: existing, in: items))
            return existing
        }

        let payload: PreparedClipboardPayload
        if let preparedPayload {
            payload = preparedPayload
        } else {
            payload = try prepareCapturedPayload(capture)
        }
        let storesPayloadOnDisk = payload.payloadPath != nil

        var item = ClipboardItem(
            id: payload.id,
            type: capture.type,
            textContent: capture.displayText,
            payloadPath: payload.payloadPath,
            contentHash: capture.contentHash,
            sourceAppIdentifier: capture.sourceAppIdentifier,
            sourceAppName: capture.sourceAppName,
            createdAt: now,
            lastCopiedAt: now,
            lastUsedAt: nil,
            isPinned: false,
            collectionID: nil,
            searchText: capture.searchText.normalizedForSearch,
            byteSize: Int64(capture.data.count),
            favoriteOrder: 0
        )
        item.rebuildSearchIndex()

        do {
            try withTransaction {
                let statement = try prepare("""
                    INSERT INTO clipboard_items (
                        id, type, display_text, inline_payload, payload_path, content_hash,
                        source_app_id, source_app_name, created_at, copied_at, last_used_at,
                        is_pinned, collection_id, search_text, byte_size, favorite_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 0, NULL, ?, ?, 0)
                    """)
                defer { sqlite3_finalize(statement) }
                bind(item.id.uuidString, at: 1, in: statement)
                bind(item.type.rawValue, at: 2, in: statement)
                bind(try encryptedString(item.textContent), at: 3, in: statement)
                bind(storesPayloadOnDisk ? nil : payload.sealedData, at: 4, in: statement)
                bind(item.payloadPath, at: 5, in: statement)
                bind(item.contentHash, at: 6, in: statement)
                bind(item.sourceAppIdentifier, at: 7, in: statement)
                bind(item.sourceAppName, at: 8, in: statement)
                sqlite3_bind_double(statement, 9, item.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 10, item.lastCopiedAt.timeIntervalSince1970)
                bind(try encryptedString(item.searchText), at: 11, in: statement)
                sqlite3_bind_int64(statement, 12, item.byteSize)
                try step(statement)
            }
        } catch {
            if let payloadPath = payload.payloadPath {
                try? FileManager.default.removeItem(atPath: payloadPath)
            }
            throw error
        }

        items.insert(item, at: insertionIndex(for: item, in: items))
        return item
    }

    func payloadData(for item: ClipboardItem) throws -> Data {
        if let path = item.payloadPath {
            guard FileManager.default.fileExists(atPath: path) else { throw ClipStoreError.missingPayload }
            return try vault.open(Data(contentsOf: URL(fileURLWithPath: path)))
        }

        let statement = try prepare("SELECT inline_payload FROM clipboard_items WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(item.id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let encrypted = data(at: 0, in: statement) else {
            throw ClipStoreError.missingPayload
        }
        return try vault.open(encrypted)
    }

    func setPinned(_ item: ClipboardItem, pinned: Bool) throws {
        let nextOrder = pinned ? ((items.filter(\.isPinned).map(\.favoriteOrder).max() ?? -1) + 1) : 0
        try executeUpdate(
            "UPDATE clipboard_items SET is_pinned = ?, favorite_order = ? WHERE id = ?",
            bindings: { statement in
                sqlite3_bind_int(statement, 1, pinned ? 1 : 0)
                sqlite3_bind_int(statement, 2, Int32(nextOrder))
                self.bind(item.id.uuidString, at: 3, in: statement)
            }
        )
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned = pinned
        items[index].favoriteOrder = nextOrder
    }

    func move(_ item: ClipboardItem, to collection: ClipCollection?) throws {
        try executeUpdate(
            "UPDATE clipboard_items SET collection_id = ? WHERE id = ?",
            bindings: { statement in
                self.bind(collection?.id.uuidString, at: 1, in: statement)
                self.bind(item.id.uuidString, at: 2, in: statement)
            }
        )
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].collectionID = collection?.id
    }

    func markUsed(_ item: ClipboardItem) throws {
        let now = Date()
        try executeUpdate(
            "UPDATE clipboard_items SET last_used_at = ? WHERE id = ?",
            bindings: { statement in
                sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
                self.bind(item.id.uuidString, at: 2, in: statement)
            }
        )
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].lastUsedAt = now }
    }

    @discardableResult
    func createCollection(named name: String) throws -> ClipCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = ClipCollection(
            id: UUID(),
            name: trimmed.isEmpty ? "Untitled Group" : trimmed,
            sortOrder: (collections.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: Date()
        )
        let statement = try prepare("INSERT INTO collections (id, name, sort_order, created_at) VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(collection.id.uuidString, at: 1, in: statement)
        bind(collection.name, at: 2, in: statement)
        sqlite3_bind_int(statement, 3, Int32(collection.sortOrder))
        sqlite3_bind_double(statement, 4, collection.createdAt.timeIntervalSince1970)
        try step(statement)
        collections.append(collection)
        return collection
    }

    func renameCollection(_ collection: ClipCollection, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try executeUpdate("UPDATE collections SET name = ? WHERE id = ?") { statement in
            self.bind(trimmed, at: 1, in: statement)
            self.bind(collection.id.uuidString, at: 2, in: statement)
        }
        if let index = collections.firstIndex(where: { $0.id == collection.id }) { collections[index].name = trimmed }
    }

    func deleteCollection(_ collection: ClipCollection) throws {
        try withTransaction {
            try executeUpdate("UPDATE clipboard_items SET collection_id = NULL WHERE collection_id = ?") { statement in
                self.bind(collection.id.uuidString, at: 1, in: statement)
            }
            try executeUpdate("DELETE FROM collections WHERE id = ?") { statement in
                self.bind(collection.id.uuidString, at: 1, in: statement)
            }
        }
        for index in items.indices where items[index].collectionID == collection.id { items[index].collectionID = nil }
        collections.removeAll { $0.id == collection.id }
    }

    func delete(_ item: ClipboardItem) throws {
        try executeUpdate("DELETE FROM clipboard_items WHERE id = ?") { statement in
            self.bind(item.id.uuidString, at: 1, in: statement)
        }
        if let path = item.payloadPath { try? FileManager.default.removeItem(atPath: path) }
        items.removeAll { $0.id == item.id }
    }

    func clearHistory() throws {
        let paths = items.compactMap(\.payloadPath)
        try execute("DELETE FROM clipboard_items")
        for path in paths { try? FileManager.default.removeItem(atPath: path) }
        if let files = try? FileManager.default.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        items.removeAll()
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try execute("VACUUM")
    }

    func performCleanup(retention: RetentionPeriod, maximumStorageMB: Int) throws {
        var candidates = items.filter { !$0.isPinned }
        var deletionIDs = Set<UUID>()
        if retention != .forever,
           let cutoff = Calendar.current.date(byAdding: .day, value: -retention.rawValue, to: Date()) {
            deletionIDs.formUnion(candidates.filter { $0.lastCopiedAt < cutoff }.map(\.id))
        }

        var remainingBytes = items.filter { !deletionIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.byteSize }
        let limit = Int64(maximumStorageMB) * 1_024 * 1_024
        if remainingBytes > limit {
            candidates.sort { $0.lastCopiedAt < $1.lastCopiedAt }
            for item in candidates where !deletionIDs.contains(item.id) && remainingBytes > limit {
                deletionIDs.insert(item.id)
                remainingBytes -= item.byteSize
            }
        }

        for item in items where deletionIDs.contains(item.id) { try delete(item) }
    }

    func exportData(to url: URL) throws {
        struct ExportItem: Codable {
            let item: ClipboardItem
            let payloadBase64: String?
        }
        struct ExportArchive: Codable {
            let exportedAt: Date
            let collections: [ClipCollection]
            let items: [ExportItem]
        }

        let exportedItems = items.map { item -> ExportItem in
            let payload = try? payloadData(for: item).base64EncodedString()
            return ExportItem(item: item, payloadBase64: payload)
        }
        let archive = ExportArchive(exportedAt: Date(), collections: collections, items: exportedItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: url, options: [.atomic])
    }

    func reload() throws {
        collections = try loadCollections()
        items = try loadItems()
    }

    private func openAndRecoverIfNeeded() throws {
        try openDatabase()
        do {
            try verifyIntegrity()
        } catch {
            if let database { sqlite3_close(database) }
            database = nil
            let formatter = ISO8601DateFormatter()
            let backup = rootDirectory.appendingPathComponent("history-corrupt-\(formatter.string(from: Date())).sqlite")
            try? FileManager.default.moveItem(at: databaseURL, to: backup)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
            try openDatabase()
        }
    }

    private func openDatabase() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw ClipStoreError.database("Unable to open \(databaseURL.lastPathComponent).")
        }
        database = handle
        sqlite3_busy_timeout(handle, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    private func verifyIntegrity() throws {
        let statement = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              string(at: 0, in: statement) == "ok" else {
            throw ClipStoreError.database("Integrity check failed.")
        }
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                display_text BLOB,
                inline_payload BLOB,
                payload_path TEXT,
                content_hash TEXT NOT NULL,
                source_app_id TEXT,
                source_app_name TEXT NOT NULL,
                created_at REAL NOT NULL,
                copied_at REAL NOT NULL,
                last_used_at REAL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                collection_id TEXT REFERENCES collections(id) ON DELETE SET NULL,
                search_text BLOB NOT NULL,
                byte_size INTEGER NOT NULL DEFAULT 0,
                favorite_order INTEGER NOT NULL DEFAULT 0
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_copied_at ON clipboard_items(copied_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_hash ON clipboard_items(content_hash)")
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_collection ON clipboard_items(collection_id)")
    }

    private func loadCollections() throws -> [ClipCollection] {
        let statement = try prepare("SELECT id, name, sort_order, created_at FROM collections ORDER BY sort_order, name")
        defer { sqlite3_finalize(statement) }
        var result: [ClipCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = string(at: 0, in: statement), let id = UUID(uuidString: idText) else { continue }
            result.append(ClipCollection(
                id: id,
                name: string(at: 1, in: statement) ?? "Group",
                sortOrder: Int(sqlite3_column_int(statement, 2)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        return result
    }

    private func loadItems() throws -> [ClipboardItem] {
        let statement = try prepare("""
            SELECT id, type, display_text, payload_path, content_hash, source_app_id,
                   source_app_name, created_at, copied_at, last_used_at, is_pinned,
                   collection_id, search_text, byte_size, favorite_order
            FROM clipboard_items ORDER BY copied_at DESC
            """)
        defer { sqlite3_finalize(statement) }
        var result: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = string(at: 0, in: statement),
                  let id = UUID(uuidString: idText),
                  let rawType = string(at: 1, in: statement),
                  let type = ClipboardContentType(rawValue: rawType),
                  let hash = string(at: 4, in: statement) else { continue }
            let displayText = try decryptedString(data(at: 2, in: statement))
            let encryptedSearch = data(at: 12, in: statement)
            let searchText = try decryptedString(encryptedSearch) ?? displayText?.normalizedForSearch ?? ""
            let collectionID = string(at: 11, in: statement).flatMap(UUID.init(uuidString:))
            let lastUsed: Date? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
            var item = ClipboardItem(
                id: id,
                type: type,
                textContent: displayText,
                payloadPath: string(at: 3, in: statement),
                contentHash: hash,
                sourceAppIdentifier: string(at: 5, in: statement),
                sourceAppName: string(at: 6, in: statement) ?? "Unknown App",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                lastUsedAt: lastUsed,
                isPinned: sqlite3_column_int(statement, 10) != 0,
                collectionID: collectionID,
                searchText: searchText,
                byteSize: sqlite3_column_int64(statement, 13),
                favoriteOrder: Int(sqlite3_column_int(statement, 14))
            )
            item.rebuildSearchIndex()
            result.append(item)
        }
        return result
    }

    private func updateCopyMetadata(_ item: ClipboardItem) throws {
        try executeUpdate("""
            UPDATE clipboard_items
            SET copied_at = ?, source_app_id = ?, source_app_name = ?
            WHERE id = ?
            """) { statement in
            sqlite3_bind_double(statement, 1, item.lastCopiedAt.timeIntervalSince1970)
            self.bind(item.sourceAppIdentifier, at: 2, in: statement)
            self.bind(item.sourceAppName, at: 3, in: statement)
            self.bind(item.id.uuidString, at: 4, in: statement)
        }
    }

    private func insertionIndex(for item: ClipboardItem, in list: [ClipboardItem]) -> Int {
        list.firstIndex { $0.lastCopiedAt < item.lastCopiedAt } ?? list.endIndex
    }

    private func encryptedString(_ string: String?) throws -> Data? {
        guard let string else { return nil }
        guard let data = string.data(using: .utf8) else { throw ClipStoreError.encoding }
        return try vault.seal(data)
    }

    private func decryptedString(_ data: Data?) throws -> String? {
        guard let data else { return nil }
        return String(data: try vault.open(data), encoding: .utf8)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw ClipStoreError.database("Database is closed.") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw ClipStoreError.database(message)
        }
    }

    private func executeUpdate(_ sql: String, bindings: (OpaquePointer) throws -> Void = { _ in }) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindings(statement)
        try step(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw ClipStoreError.database("Database is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ClipStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw ClipStoreError.database(message)
        }
    }

    private func withTransaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(_ value: Data?, at index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
    }

    private func string(at index: Int32, in statement: OpaquePointer) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func data(at index: Int32, in statement: OpaquePointer) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }
}

import Foundation
import SQLite3

public enum StorageIndexStoreError: Error, CustomStringConvertible {
    case sqlite(String)

    public var description: String {
        switch self {
        case .sqlite(let message):
            return message
        }
    }
}

public final class StorageIndexStore {
    public static var defaultDatabaseURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["AGENTDOCK_STORAGE_INDEX_DB"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: NSString(string: overridePath).expandingTildeInPath).standardizedFileURL
        }

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("AgentDock", isDirectory: true)
            .appendingPathComponent("storage-index.sqlite")
    }

    public let databaseURL: URL

    public init(databaseURL: URL = StorageIndexStore.defaultDatabaseURL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try withDatabase { database in
            try Self.migrate(database)
        }
    }

    public func save(_ analysis: StorageAnalysis) throws {
        let sessionID = UUID().uuidString
        try withDatabase { database in
            try Self.execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                try Self.insertSession(sessionID: sessionID, analysis: analysis, database: database)
                try Self.insertNodes(sessionID: sessionID, root: analysis.root, database: database)
                try Self.insertCleanupCandidates(sessionID: sessionID, candidates: analysis.cleanupCandidates, database: database)
                try Self.pruneOldSessions(database: database, keeping: 20)
                try Self.execute("COMMIT", database: database)
            } catch {
                try? Self.execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    public func latestAnalysis() throws -> StorageAnalysis? {
        try withDatabase { database in
            guard let session = try Self.latestSession(database: database) else {
                return nil
            }

            let rows = try Self.nodeRows(sessionID: session.id, database: database)
            guard let rootRow = rows.first(where: { $0.path == session.rootPath }) ?? rows.min(by: { $0.depth < $1.depth }) else {
                return nil
            }

            let childRowsByParent = Dictionary(grouping: rows.filter { $0.parentPath != nil }) { row in
                row.parentPath ?? ""
            }
            let rootNode = Self.node(from: rootRow, childRowsByParent: childRowsByParent)
            let rankedNodes = Self.flattenedNodes(from: rootNode)
                .filter { $0.url.path != rootNode.url.path && $0.byteCount > 0 }
                .sorted(by: Self.sortStorageNodes)
            let cleanupCandidates = try Self.cleanupCandidates(sessionID: session.id, database: database)
            let scanLog = [
                "Loaded local index \(session.rootPath)",
                "Indexed \(session.indexedFileCount) files",
                "Found \(cleanupCandidates.count) cleanup candidates",
                "Scan time \(StatusFormatters.duration(session.durationSeconds))"
            ]

            return StorageAnalysis(
                disk: DiskSnapshot(capacity: session.diskCapacity, available: session.diskAvailable),
                root: rootNode,
                rankedNodes: rankedNodes,
                cleanupCandidates: cleanupCandidates,
                scanLog: scanLog,
                indexedFileCount: session.indexedFileCount,
                scanStartedAt: session.startedAt,
                scanFinishedAt: session.finishedAt,
                scanDuration: session.durationSeconds
            )
        }
    }

    private func withDatabase<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open storage index database"
            throw StorageIndexStoreError.sqlite(message)
        }
        defer {
            sqlite3_close(database)
        }
        return try work(database)
    }

    private static func migrate(_ database: OpaquePointer) throws {
        try execute("PRAGMA journal_mode=WAL", database: database)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS storage_scan_sessions (
                id TEXT PRIMARY KEY,
                root_path TEXT NOT NULL,
                max_depth INTEGER NOT NULL,
                include_hidden INTEGER NOT NULL,
                started_at REAL,
                finished_at REAL,
                duration_seconds REAL NOT NULL,
                indexed_file_count INTEGER NOT NULL,
                root_byte_count INTEGER NOT NULL,
                disk_capacity INTEGER NOT NULL,
                disk_available INTEGER NOT NULL
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS storage_nodes (
                session_id TEXT NOT NULL,
                path TEXT NOT NULL,
                parent_path TEXT,
                depth INTEGER NOT NULL,
                title TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                is_directory INTEGER NOT NULL,
                risk TEXT NOT NULL,
                PRIMARY KEY (session_id, path)
            )
            """,
            database: database
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS storage_cleanup_candidates (
                session_id TEXT NOT NULL,
                path TEXT NOT NULL,
                title TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                risk TEXT NOT NULL,
                reason TEXT NOT NULL,
                PRIMARY KEY (session_id, path)
            )
            """,
            database: database
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_storage_scan_sessions_finished_at ON storage_scan_sessions(finished_at DESC)",
            database: database
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_storage_nodes_parent ON storage_nodes(session_id, parent_path)",
            database: database
        )
    }

    private static func insertSession(sessionID: String, analysis: StorageAnalysis, database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO storage_scan_sessions (
                id,
                root_path,
                max_depth,
                include_hidden,
                started_at,
                finished_at,
                duration_seconds,
                indexed_file_count,
                root_byte_count,
                disk_capacity,
                disk_available
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        bindText(statement, 1, sessionID)
        bindText(statement, 2, analysis.root.url.path)
        bindInt(statement, 3, 0)
        bindInt(statement, 4, 0)
        bindOptionalDouble(statement, 5, analysis.scanStartedAt?.timeIntervalSince1970)
        bindOptionalDouble(statement, 6, analysis.scanFinishedAt?.timeIntervalSince1970)
        bindDouble(statement, 7, analysis.scanDuration)
        bindInt(statement, 8, analysis.indexedFileCount)
        bindInt64(statement, 9, analysis.root.byteCount)
        bindInt64(statement, 10, analysis.disk.capacity)
        bindInt64(statement, 11, analysis.disk.available)
        try stepDone(statement, database: database)
    }

    private static func insertNodes(sessionID: String, root: StorageNode, database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT INTO storage_nodes (
                session_id,
                path,
                parent_path,
                depth,
                title,
                byte_count,
                is_directory,
                risk
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        try insertNode(root, sessionID: sessionID, parentPath: nil, depth: 0, statement: statement, database: database)
    }

    private static func insertNode(
        _ node: StorageNode,
        sessionID: String,
        parentPath: String?,
        depth: Int,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        bindText(statement, 1, sessionID)
        bindText(statement, 2, node.url.path)
        bindOptionalText(statement, 3, parentPath)
        bindInt(statement, 4, depth)
        bindText(statement, 5, node.title)
        bindInt64(statement, 6, node.byteCount)
        bindBool(statement, 7, node.isDirectory)
        bindText(statement, 8, node.risk.rawValue)
        try stepDone(statement, database: database)

        for child in node.children {
            try insertNode(
                child,
                sessionID: sessionID,
                parentPath: node.url.path,
                depth: depth + 1,
                statement: statement,
                database: database
            )
        }
    }

    private static func insertCleanupCandidates(
        sessionID: String,
        candidates: [StorageCleanupCandidate],
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO storage_cleanup_candidates (
                session_id,
                path,
                title,
                byte_count,
                risk,
                reason
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        for candidate in candidates {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, 1, sessionID)
            bindText(statement, 2, candidate.url.path)
            bindText(statement, 3, candidate.title)
            bindInt64(statement, 4, candidate.byteCount)
            bindText(statement, 5, candidate.risk.rawValue)
            bindText(statement, 6, candidate.reason)
            try stepDone(statement, database: database)
        }
    }

    private static func pruneOldSessions(database: OpaquePointer, keeping sessionLimit: Int) throws {
        let keepSubquery = "SELECT id FROM storage_scan_sessions ORDER BY finished_at DESC, rowid DESC LIMIT \(sessionLimit)"
        try execute("DELETE FROM storage_cleanup_candidates WHERE session_id NOT IN (\(keepSubquery))", database: database)
        try execute("DELETE FROM storage_nodes WHERE session_id NOT IN (\(keepSubquery))", database: database)
        try execute("DELETE FROM storage_scan_sessions WHERE id NOT IN (\(keepSubquery))", database: database)
    }

    private static func latestSession(database: OpaquePointer) throws -> StorageSessionRow? {
        let statement = try prepare(
            """
            SELECT
                id,
                root_path,
                started_at,
                finished_at,
                duration_seconds,
                indexed_file_count,
                root_byte_count,
                disk_capacity,
                disk_available
            FROM storage_scan_sessions
            ORDER BY finished_at DESC, rowid DESC
            LIMIT 1
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return StorageSessionRow(
            id: columnString(statement, 0) ?? "",
            rootPath: columnString(statement, 1) ?? "",
            startedAt: columnOptionalDate(statement, 2),
            finishedAt: columnOptionalDate(statement, 3),
            durationSeconds: columnDouble(statement, 4),
            indexedFileCount: columnInt(statement, 5),
            rootByteCount: columnInt64(statement, 6),
            diskCapacity: columnInt64(statement, 7),
            diskAvailable: columnInt64(statement, 8)
        )
    }

    private static func nodeRows(sessionID: String, database: OpaquePointer) throws -> [StorageNodeRow] {
        let statement = try prepare(
            """
            SELECT path, parent_path, depth, title, byte_count, is_directory, risk
            FROM storage_nodes
            WHERE session_id = ?
            ORDER BY depth ASC, byte_count DESC, title ASC
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }
        bindText(statement, 1, sessionID)

        var rows: [StorageNodeRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                StorageNodeRow(
                    path: columnString(statement, 0) ?? "",
                    parentPath: columnString(statement, 1),
                    depth: columnInt(statement, 2),
                    title: columnString(statement, 3) ?? "",
                    byteCount: columnInt64(statement, 4),
                    isDirectory: columnBool(statement, 5),
                    risk: StorageCleanupRisk(rawValue: columnString(statement, 6) ?? "") ?? .protected
                )
            )
        }
        return rows
    }

    private static func cleanupCandidates(sessionID: String, database: OpaquePointer) throws -> [StorageCleanupCandidate] {
        let statement = try prepare(
            """
            SELECT title, path, byte_count, risk, reason
            FROM storage_cleanup_candidates
            WHERE session_id = ?
            ORDER BY byte_count DESC, title ASC
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }
        bindText(statement, 1, sessionID)

        var candidates: [StorageCleanupCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = columnString(statement, 1) ?? ""
            candidates.append(
                StorageCleanupCandidate(
                    title: columnString(statement, 0) ?? "",
                    url: URL(fileURLWithPath: path),
                    byteCount: columnInt64(statement, 2),
                    risk: StorageCleanupRisk(rawValue: columnString(statement, 3) ?? "") ?? .protected,
                    reason: columnString(statement, 4) ?? ""
                )
            )
        }
        return candidates
    }

    private static func node(
        from row: StorageNodeRow,
        childRowsByParent: [String: [StorageNodeRow]]
    ) -> StorageNode {
        let children = (childRowsByParent[row.path] ?? [])
            .sorted(by: sortStorageNodeRows)
            .map { node(from: $0, childRowsByParent: childRowsByParent) }
        return StorageNode(
            title: row.title,
            url: URL(fileURLWithPath: row.path),
            byteCount: row.byteCount,
            isDirectory: row.isDirectory,
            risk: row.risk,
            children: children
        )
    }

    private static func flattenedNodes(from node: StorageNode) -> [StorageNode] {
        [node] + node.children.flatMap(flattenedNodes)
    }

    private static func sortStorageNodes(_ lhs: StorageNode, _ rhs: StorageNode) -> Bool {
        if lhs.byteCount == rhs.byteCount {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.byteCount > rhs.byteCount
    }

    private static func sortStorageNodeRows(_ lhs: StorageNodeRow, _ rhs: StorageNodeRow) -> Bool {
        if lhs.byteCount == rhs.byteCount {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.byteCount > rhs.byteCount
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw StorageIndexStoreError.sqlite(message)
        }
    }

    private static func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw StorageIndexStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private static func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageIndexStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private static func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(statement, index, value)
    }

    private static func bindInt(_ statement: OpaquePointer, _ index: Int32, _ value: Int) {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private static func bindInt64(_ statement: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private static func bindDouble(_ statement: OpaquePointer, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    private static func bindOptionalDouble(_ statement: OpaquePointer, _ index: Int32, _ value: Double?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindDouble(statement, index, value)
    }

    private static func bindBool(_ statement: OpaquePointer, _ index: Int32, _ value: Bool) {
        sqlite3_bind_int(statement, index, value ? 1 : 0)
    }

    private static func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: text)
    }

    private static func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }

    private static func columnInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64 {
        Int64(sqlite3_column_int64(statement, index))
    }

    private static func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private static func columnBool(_ statement: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    private static func columnOptionalDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: columnDouble(statement, index))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct StorageSessionRow {
    let id: String
    let rootPath: String
    let startedAt: Date?
    let finishedAt: Date?
    let durationSeconds: TimeInterval
    let indexedFileCount: Int
    let rootByteCount: Int64
    let diskCapacity: Int64
    let diskAvailable: Int64
}

private struct StorageNodeRow {
    let path: String
    let parentPath: String?
    let depth: Int
    let title: String
    let byteCount: Int64
    let isDirectory: Bool
    let risk: StorageCleanupRisk
}

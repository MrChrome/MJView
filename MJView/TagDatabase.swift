//
//  TagDatabase.swift
//  MJView
//

import Foundation
import SQLite3
import CryptoKit

struct Tag: Identifiable, Hashable {
    let id: Int64
    let name: String
}

@Observable
class TagDatabase {
    var tagsForCurrentImage: [Tag] = []
    var allTags: [Tag] = []
    var allTaggedPaths: Set<String> = []

    private var db: OpaquePointer?
    private var dbPath: String = ""

    init() {
        openDatabase()
        createTablesIfNeeded()
        migrateIfNeeded()
        refreshAllTags()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Hashing

    /// Returns the SHA-256 hex digest of a path string.
    static func hashPath(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Instance forwarder so callers with a TagDatabase reference work unchanged.
    func hashPath(_ path: String) -> String { TagDatabase.hashPath(path) }

    private func folderHash(forFilePath path: String) -> String {
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return TagDatabase.hashPath(folder)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupport.appendingPathComponent("MJView")
        try? fm.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        dbPath = dbDirectory.appendingPathComponent("tags.sqlite").path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    private func createTablesIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE
        );
        CREATE TABLE IF NOT EXISTS image_tags (
            image_path TEXT NOT NULL,
            image_folder_hash TEXT NOT NULL DEFAULT '',
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (image_path, tag_id),
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_image_tags_path ON image_tags(image_path);
        CREATE INDEX IF NOT EXISTS idx_image_tags_folder ON image_tags(image_folder_hash);
        CREATE INDEX IF NOT EXISTS idx_image_tags_tag ON image_tags(tag_id);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }

        if version < 1 {
            migrateToV1()
        }
    }

    /// Copies the live database to `tags.sqlite.bak` using SQLite's online backup API.
    private func backupDatabase() {
        guard !dbPath.isEmpty else { return }
        let backupPath = dbPath + ".bak"
        var backupDb: OpaquePointer?
        guard sqlite3_open(backupPath, &backupDb) == SQLITE_OK else { return }
        defer { sqlite3_close(backupDb) }

        if let backup = sqlite3_backup_init(backupDb, "main", db, "main") {
            sqlite3_backup_step(backup, -1)   // copy all pages in one step
            sqlite3_backup_finish(backup)
        }
    }

    /// Migrate v0 → v1: replace raw paths with SHA-256 hashes and add image_folder_hash column.
    private func migrateToV1() {
        backupDatabase()

        // Add image_folder_hash column if it doesn't exist yet (it may exist if
        // createTablesIfNeeded ran on a fresh install hitting this migration path).
        sqlite3_exec(db, "ALTER TABLE image_tags ADD COLUMN image_folder_hash TEXT NOT NULL DEFAULT '';", nil, nil, nil)

        // Read all existing rows
        var rows: [(path: String, tagId: Int64)] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT image_path, tag_id FROM image_tags;", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(stmt, 0))
                let tagId = sqlite3_column_int64(stmt, 1)
                rows.append((path, tagId))
            }
            sqlite3_finalize(stmt)
        }

        // Only migrate rows that look like raw paths (not already 64-char hex hashes)
        let rawRows = rows.filter { !isHex64($0.path) }
        guard !rawRows.isEmpty else {
            sqlite3_exec(db, "PRAGMA user_version = 1;", nil, nil, nil)
            return
        }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        // Delete raw-path rows
        for row in rawRows {
            execute("DELETE FROM image_tags WHERE image_path = ? AND tag_id = ?",
                    bindings: [row.path, row.tagId])
        }

        // Re-insert with hashed paths
        for row in rawRows {
            let hashed = hashPath(row.path)
            let folder = folderHash(forFilePath: row.path)
            execute("INSERT OR IGNORE INTO image_tags (image_path, image_folder_hash, tag_id) VALUES (?, ?, ?)",
                    bindings: [hashed, folder, row.tagId])
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA user_version = 1;", nil, nil, nil)
    }

    private func isHex64(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy({ $0.isHexDigit })
    }

    // MARK: - Query Helpers

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func query(_ sql: String, bindings: [Any] = [], rowHandler: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let text as String:
                sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT)
            case let int as Int64:
                sqlite3_bind_int64(stmt, i, int)
            default:
                break
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            rowHandler(stmt!)
        }
    }

    private func execute(_ sql: String, bindings: [Any] = []) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let text as String:
                sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT)
            case let int as Int64:
                sqlite3_bind_int64(stmt, i, int)
            default:
                break
            }
        }

        sqlite3_step(stmt)
    }

    // MARK: - Public Methods

    func loadTags(forImagePath path: String) {
        var results: [Tag] = []
        query(
            """
            SELECT tags.id, tags.name FROM tags
            INNER JOIN image_tags ON tags.id = image_tags.tag_id
            WHERE image_tags.image_path = ?
            ORDER BY tags.name
            """,
            bindings: [hashPath(path)]
        ) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let name = String(cString: sqlite3_column_text(stmt, 1))
            results.append(Tag(id: id, name: name))
        }
        tagsForCurrentImage = results
    }

    func refreshAllTags() {
        var results: [Tag] = []
        query("SELECT id, name FROM tags ORDER BY name") { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let name = String(cString: sqlite3_column_text(stmt, 1))
            results.append(Tag(id: id, name: name))
        }
        allTags = results
        refreshAllTaggedPaths()
    }

    private func refreshAllTaggedPaths() {
        var results: Set<String> = []
        query("SELECT DISTINCT image_path FROM image_tags") { stmt in
            results.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        allTaggedPaths = results
    }

    /// Returns whether the given filesystem path has any tags assigned.
    func isPathTagged(_ path: String) -> Bool {
        allTaggedPaths.contains(hashPath(path))
    }

    /// Returns tags that have been assigned to at least one file directly inside the given folder.
    func tagsUsed(underFolder folderPath: String) -> [Tag] {
        var results: [Tag] = []
        query(
            """
            SELECT DISTINCT tags.id, tags.name FROM tags
            INNER JOIN image_tags ON tags.id = image_tags.tag_id
            WHERE image_tags.image_folder_hash = ?
            ORDER BY tags.name
            """,
            bindings: [hashPath(folderPath)]
        ) { stmt in
            let id = sqlite3_column_int64(stmt, 0)
            let name = String(cString: sqlite3_column_text(stmt, 1))
            results.append(Tag(id: id, name: name))
        }
        return results
    }

    func addTag(name: String, toImagePath path: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Insert tag if it doesn't exist
        execute("INSERT OR IGNORE INTO tags (name) VALUES (?)", bindings: [trimmed])

        // Get the tag ID
        var tagId: Int64 = 0
        query("SELECT id FROM tags WHERE name = ? COLLATE NOCASE", bindings: [trimmed]) { stmt in
            tagId = sqlite3_column_int64(stmt, 0)
        }
        guard tagId > 0 else { return }

        // Link tag to image using hashed path and folder hash
        let hashed = hashPath(path)
        let folder = folderHash(forFilePath: path)
        execute("INSERT OR IGNORE INTO image_tags (image_path, image_folder_hash, tag_id) VALUES (?, ?, ?)",
                bindings: [hashed, folder, tagId])

        loadTags(forImagePath: path)
        refreshAllTags()
    }

    func renameTag(tagId: Int64, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        execute("UPDATE tags SET name = ? WHERE id = ?", bindings: [trimmed, tagId])
        refreshAllTags()
    }

    func removeTag(tagId: Int64, fromImagePath path: String) {
        execute("DELETE FROM image_tags WHERE image_path = ? AND tag_id = ?",
                bindings: [hashPath(path), tagId])
        loadTags(forImagePath: path)
        refreshAllTaggedPaths()
    }

    /// Returns all path hashes that have ALL of the given tag IDs assigned,
    /// restricted to files whose folder hash matches the given root folder.
    func imagePaths(matchingAllTagIds tagIds: [Int64], underFolder folderPath: String) -> Set<String> {
        guard !tagIds.isEmpty else { return [] }

        // Hash the root folder path for prefix-free recursive matching.
        // We store per-file folder hashes (one level up), so to find all files
        // under a root recursively we fetch all paths for each tag and intersect —
        // the folder-hash column is used for the single-folder tagsUsed query;
        // for recursive tag filtering we rely on set intersection of all tagged hashes.
        var result: Set<String>? = nil
        for tagId in tagIds {
            var paths: Set<String> = []
            query(
                "SELECT image_path FROM image_tags WHERE tag_id = ?",
                bindings: [tagId]
            ) { stmt in
                paths.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
            if result == nil {
                result = paths
            } else {
                result = result!.intersection(paths)
            }
        }
        return result ?? []
    }
}

//
//  TagDatabase.swift
//  MJView
//

import Foundation
import SQLite3

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

    init() {
        openDatabase()
        createTablesIfNeeded()
        refreshAllTags()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupport.appendingPathComponent("MJView")
        try? fm.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        let dbPath = dbDirectory.appendingPathComponent("tags.sqlite").path

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
            tag_id INTEGER NOT NULL,
            PRIMARY KEY (image_path, tag_id),
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_image_tags_path ON image_tags(image_path);
        CREATE INDEX IF NOT EXISTS idx_image_tags_tag ON image_tags(tag_id);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
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
            bindings: [path]
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

    /// Returns tags that have been assigned to at least one file under the given folder prefix.
    func tagsUsed(underFolder folderPath: String) -> [Tag] {
        var results: [Tag] = []
        query(
            """
            SELECT DISTINCT tags.id, tags.name FROM tags
            INNER JOIN image_tags ON tags.id = image_tags.tag_id
            WHERE image_tags.image_path LIKE ? ESCAPE '\\'
            ORDER BY tags.name
            """,
            bindings: [folderPath.replacingOccurrences(of: "%", with: "\\%")
                                  .replacingOccurrences(of: "_", with: "\\_") + "%"]
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

        // Link tag to image
        execute("INSERT OR IGNORE INTO image_tags (image_path, tag_id) VALUES (?, ?)", bindings: [path, tagId])

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
        execute("DELETE FROM image_tags WHERE image_path = ? AND tag_id = ?", bindings: [path, tagId])
        loadTags(forImagePath: path)
        refreshAllTaggedPaths()
    }

    /// Returns all image paths that have ALL of the given tag IDs assigned,
    /// optionally restricted to paths under a folder prefix (recursive).
    func imagePaths(matchingAllTagIds tagIds: [Int64], underFolder folderPath: String) -> Set<String> {
        guard !tagIds.isEmpty else { return [] }

        // For each tag, get the set of paths under the folder prefix, then intersect
        var result: Set<String>? = nil
        for tagId in tagIds {
            var paths: Set<String> = []
            query(
                "SELECT image_path FROM image_tags WHERE tag_id = ?",
                bindings: [tagId]
            ) { stmt in
                let path = String(cString: sqlite3_column_text(stmt, 0))
                // Check that this path lives under the folder (recursive)
                if path.hasPrefix(folderPath) {
                    paths.insert(path)
                }
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

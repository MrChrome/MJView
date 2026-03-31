//
//  ThumbnailDatabase.swift
//  MJView
//

import Foundation
import AppKit
import SQLite3

/// Persists thumbnail images to SQLite so re-visiting a folder (or restarting
/// the app) doesn't require re-reading image files from the network.
///
/// Cache hierarchy used by AsyncThumbnailImage:
///   1. ThumbnailCache  — in-memory NSCache (no async overhead)
///   2. ThumbnailDatabase — this actor (SQLite on disk, fast local read)
///   3. File / network   — CGImageSource or AVFoundation decode
actor ThumbnailDatabase {
    static let shared = ThumbnailDatabase()

    private var db: OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        // Actor designated inits are nonisolated in Swift 6, so we inline all
        // setup here rather than calling actor-isolated helper methods.
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MJView")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("thumbnails.sqlite").path

        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)

        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS thumbnails (
                path_hash   TEXT    NOT NULL,
                size_bucket INTEGER NOT NULL,
                mod_date    REAL    NOT NULL,
                image_data  BLOB    NOT NULL,
                accessed_at REAL    NOT NULL DEFAULT 0,
                PRIMARY KEY (path_hash, size_bucket)
            );
        """, nil, nil, nil)

        let cutoff = Date().addingTimeInterval(-60 * 24 * 60 * 60).timeIntervalSinceReferenceDate
        sqlite3_exec(db, "DELETE FROM thumbnails WHERE accessed_at < \(cutoff);", nil, nil, nil)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Public API

    /// Returns a cached thumbnail if one exists and its mod-date still matches.
    /// Also updates the accessed_at timestamp so the entry isn't pruned.
    func image(for url: URL, size: CGFloat, modifiedDate: Date) -> NSImage? {
        let pathHash = Self.hashPath(url.path)
        let sizeBucket = Int64(size)
        let modTime = modifiedDate.timeIntervalSinceReferenceDate

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT image_data FROM thumbnails WHERE path_hash = ? AND size_bucket = ? AND mod_date = ?",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, pathHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, sizeBucket)
        sqlite3_bind_double(stmt, 3, modTime)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let bytes = sqlite3_column_blob(stmt, 0)
        let length = Int(sqlite3_column_bytes(stmt, 0))
        guard let bytes, length > 0,
              let image = NSImage(data: Data(bytes: bytes, count: length)) else { return nil }

        // Touch accessed_at so frequently-used entries survive pruning
        touchEntry(pathHash: pathHash, sizeBucket: sizeBucket)
        return image
    }

    /// Compresses and stores a thumbnail. Uses INSERT OR REPLACE so a changed
    /// mod_date on the same file automatically evicts the stale entry.
    /// Cloud-only thumbnails are skipped — they are placeholder icons, not real images.
    func store(_ image: NSImage, for url: URL, size: CGFloat, modifiedDate: Date, isCloudOnly: Bool) {
        guard !isCloudOnly else { return }
        guard let data = jpegData(from: image) else { return }

        let pathHash = Self.hashPath(url.path)
        let sizeBucket = Int64(size)
        let modTime = modifiedDate.timeIntervalSinceReferenceDate
        let now = Date().timeIntervalSinceReferenceDate

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "INSERT OR REPLACE INTO thumbnails (path_hash, size_bucket, mod_date, image_data, accessed_at) VALUES (?, ?, ?, ?, ?)",
            -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, pathHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, sizeBucket)
        sqlite3_bind_double(stmt, 3, modTime)
        _ = data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_double(stmt, 5, now)
        sqlite3_step(stmt)
    }

    // MARK: - Private

    private func touchEntry(pathHash: String, sizeBucket: Int64) {
        let now = Date().timeIntervalSinceReferenceDate
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "UPDATE thumbnails SET accessed_at = ? WHERE path_hash = ? AND size_bucket = ?",
            -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, pathHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, sizeBucket)
        sqlite3_step(stmt)
    }

    /// Compresses an NSImage to JPEG for compact storage.
    private func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// Fast FNV-1a hash used as a compact, collision-resistant cache key.
    private static func hashPath(_ path: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

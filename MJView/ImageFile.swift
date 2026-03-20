//
//  ImageFile.swift
//  MJView
//

import Foundation
import AppKit

struct FolderItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var createdDate: Date = .distantPast
    var modifiedDate: Date = .distantPast

    func hash(into hasher: inout Hasher) { hasher.combine(url) }
    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool { lhs.url == rhs.url }
}

struct ImageFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let fileSize: Int64
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var createdDate: Date = .distantPast
    var modifiedDate: Date = .distantPast
    var isVideo: Bool = false
    var isAnimated: Bool = false

    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var dimensionString: String {
        if pixelWidth > 0 && pixelHeight > 0 {
            return "\(pixelWidth) × \(pixelHeight)"
        }
        return ""
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.url == rhs.url
    }
}

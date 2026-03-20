//
//  ImageLoader.swift
//  MJView
//

import Foundation
import AppKit
import SwiftUI

@Observable
class ImageLoader {
    var images: [ImageFile] = []
    var subfolders: [FolderItem] = []
    var currentFolder: URL?
    var rootFolder: URL?
    var isLoading = false
    var needsFolderSelection = false
    var recentFolders: [URL] = []

    /// When non-nil, the grid shows only these files (tag filter results)
    var tagFilteredImages: [ImageFile]? = nil
    var isFilterActive: Bool { tagFilteredImages != nil }

    // The URL currently holding an open security-scoped access grant
    private var accessedURL: URL?

    private static let recentFoldersKey = "recentFolders"
    private static let maxRecentFolders = 5

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "flv", "webm", "mpg", "mpeg", "3gp"
    ]
    private static var supportedExtensions: Set<String> {
        imageExtensions.union(videoExtensions)
    }

    /// Whether we can navigate up from the current folder
    var canGoUp: Bool {
        guard let current = currentFolder, let root = rootFolder else { return false }
        return current != root
    }

    private static var defaultFolderURL: URL {
        let realHome: String
        if let pw = getpwuid(getuid()), let homeDir = pw.pointee.pw_dir {
            realHome = String(cString: homeDir)
        } else {
            realHome = NSHomeDirectory()
        }
        return URL(fileURLWithPath: realHome)
    }

    init() {
        loadRecentFolders()
        needsFolderSelection = true
    }

    private func loadRecentFolders() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.recentFoldersKey) as? [Data] else { return }
        var refreshed: [Data] = []
        var urls: [URL] = []
        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            // Re-save stale bookmarks (e.g. volume remounted at new path)
            let freshData = isStale ? (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) : data
            if let freshData {
                refreshed.append(freshData)
                urls.append(url)
            }
        }
        if refreshed.count != bookmarks.count {
            UserDefaults.standard.set(refreshed, forKey: Self.recentFoldersKey)
        }
        recentFolders = urls
    }

    private func saveRecentFolders() {
        let bookmarks = recentFolders.compactMap {
            try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.recentFoldersKey)
    }

    private func addToRecentFolders(_ url: URL) {
        recentFolders.removeAll { $0 == url }
        recentFolders.insert(url, at: 0)
        if recentFolders.count > Self.maxRecentFolders {
            recentFolders = Array(recentFolders.prefix(Self.maxRecentFolders))
        }
        saveRecentFolders()
    }

    func loadFolder(_ url: URL, isRoot: Bool = false) {
        if isRoot {
            // Start access on the new root before stopping the old one
            let didGainAccess = url.startAccessingSecurityScopedResource()
            // Stop access on the previous root
            if let previous = accessedURL {
                previous.stopAccessingSecurityScopedResource()
            }
            accessedURL = didGainAccess ? url : nil
            rootFolder = url
            addToRecentFolders(url)
        }

        currentFolder = url
        isLoading = true
        images = []
        subfolders = []
        needsFolderSelection = false

        Task.detached { [weak self] in
            guard let self else { return }
            let (loadedImages, loadedSubfolders) = Self.scanFolder(url)
            await MainActor.run {
                self.images = loadedImages
                self.subfolders = loadedSubfolders
                self.isLoading = false
            }
        }
    }

    func navigateToSubfolder(_ url: URL) {
        loadFolder(url)
    }

    func navigateUp() {
        guard let current = currentFolder, canGoUp else { return }
        let parent = current.deletingLastPathComponent()
        loadFolder(parent)
    }

    private static func scanFolder(_ url: URL) -> (images: [ImageFile], subfolders: [FolderItem]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return ([], []) }

        var imageResults: [ImageFile] = []
        var folderResults: [FolderItem] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey]) else { continue }

            if resourceValues.isDirectory == true {
                let folder = FolderItem(
                    url: fileURL,
                    createdDate: resourceValues.creationDate ?? .distantPast,
                    modifiedDate: resourceValues.contentModificationDate ?? .distantPast
                )
                folderResults.append(folder)
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let isVideo = videoExtensions.contains(ext)
            var imageFile = ImageFile(
                url: fileURL,
                name: fileURL.lastPathComponent,
                fileSize: fileSize,
                createdDate: resourceValues.creationDate ?? .distantPast,
                modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
                isVideo: isVideo
            )

            // Get pixel dimensions (images only)
            if !isVideo,
               let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                if let w = properties[kCGImagePropertyPixelWidth] as? Int,
                   let h = properties[kCGImagePropertyPixelHeight] as? Int {
                    imageFile.pixelWidth = w
                    imageFile.pixelHeight = h
                }
            }

            imageResults.append(imageFile)
        }

        imageResults.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        folderResults.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (imageResults, folderResults)
    }

    func applyTagFilter(matchingPaths: Set<String>) {
        guard let root = rootFolder else { return }
        isLoading = true
        tagFilteredImages = nil

        Task.detached { [weak self] in
            guard let self else { return }
            let didGainAccess = root.startAccessingSecurityScopedResource()
            let results = Self.scanAllFiles(under: root, matchingPaths: matchingPaths)
            if didGainAccess { root.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                self.tagFilteredImages = results
                self.isLoading = false
            }
        }
    }

    func clearTagFilter() {
        tagFilteredImages = nil
    }

    /// Recursively scans all files under a root URL, returning only those whose path is in matchingPaths.
    private static func scanAllFiles(under root: URL, matchingPaths: Set<String>) -> [ImageFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [ImageFile] = []
        for case let fileURL as URL in enumerator {
            guard matchingPaths.contains(fileURL.path) else { continue }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .creationDateKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let isVideo = videoExtensions.contains(ext)
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            var imageFile = ImageFile(
                url: fileURL,
                name: fileURL.lastPathComponent,
                fileSize: fileSize,
                createdDate: resourceValues.creationDate ?? .distantPast,
                modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
                isVideo: isVideo
            )
            if !isVideo,
               let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                imageFile.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                imageFile.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
            results.append(imageFile)
        }
        results.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return results
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing images"
        panel.directoryURL = Self.defaultFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            loadFolder(url, isRoot: true)
        }
    }
}

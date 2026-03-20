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
    var subfolders: [URL] = []
    var currentFolder: URL?
    var rootFolder: URL?
    var isLoading = false
    var needsFolderSelection = false
    var recentFolders: [URL] = []

    // The URL currently holding an open security-scoped access grant
    private var accessedURL: URL?

    private static let recentFoldersKey = "recentFolders"
    private static let maxRecentFolders = 5

    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns"
    ]

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

    private static func scanFolder(_ url: URL) -> (images: [ImageFile], subfolders: [URL]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return ([], []) }

        var imageResults: [ImageFile] = []
        var folderResults: [URL] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey]) else { continue }

            if resourceValues.isDirectory == true {
                folderResults.append(fileURL)
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let fileSize = Int64(resourceValues.fileSize ?? 0)
            var imageFile = ImageFile(
                url: fileURL,
                name: fileURL.lastPathComponent,
                fileSize: fileSize,
                createdDate: resourceValues.creationDate ?? .distantPast,
                modifiedDate: resourceValues.contentModificationDate ?? .distantPast
            )

            // Get pixel dimensions
            if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
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
        folderResults.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return (imageResults, folderResults)
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

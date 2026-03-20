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

    /// Set after a cloud file finishes downloading, so views can refresh.
    var lastDownloadedFileId: UUID?

    // The URL currently holding an open security-scoped access grant
    var accessedURL: URL?

    // Filesystem watcher for the current folder
    private var folderWatchSource: DispatchSourceFileSystemObject?
    private var folderWatchFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?

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

            if isStale {
                // Must start security-scoped access before creating a new bookmark
                let accessed = url.startAccessingSecurityScopedResource()
                let freshData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                if accessed { url.stopAccessingSecurityScopedResource() }
                if let freshData {
                    refreshed.append(freshData)
                    urls.append(url)
                }
            } else {
                refreshed.append(data)
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
        startWatching(url)

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

    private func startWatching(_ url: URL) {
        stopWatching()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderWatchFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        folderWatchSource = source
    }

    private func stopWatching() {
        folderWatchSource?.cancel()
        folderWatchSource = nil
        folderWatchFD = -1
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let url = self.currentFolder else { return }
            let (loadedImages, loadedSubfolders) = await Task.detached {
                Self.scanFolder(url)
            }.value
            self.images = loadedImages
            self.subfolders = loadedSubfolders
        }
    }

    /// Check whether a file URL refers to a ubiquitous (iCloud) item that has
    /// not been downloaded to the local device yet.
    private static func isCloudOnlyFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) else {
            return false
        }
        guard values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }

    private static func scanFolder(_ url: URL) -> (images: [ImageFile], subfolders: [FolderItem]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
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
            let cloudOnly = isCloudOnlyFile(fileURL)
            var imageFile = ImageFile(
                url: fileURL,
                name: fileURL.lastPathComponent,
                fileSize: fileSize,
                createdDate: resourceValues.creationDate ?? .distantPast,
                modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
                isVideo: isVideo,
                isCloudOnly: cloudOnly
            )

            // Get pixel dimensions and animation state (images only).
            // Skip for cloud-only files to avoid triggering a download.
            if !isVideo, !cloudOnly,
               let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
                if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                    if let w = properties[kCGImagePropertyPixelWidth] as? Int,
                       let h = properties[kCGImagePropertyPixelHeight] as? Int {
                        imageFile.pixelWidth = w
                        imageFile.pixelHeight = h
                    }
                }
                imageFile.isAnimated = CGImageSourceGetCount(imageSource) > 1
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

    func removeImage(_ image: ImageFile) {
        images.removeAll { $0.id == image.id }
        tagFilteredImages?.removeAll { $0.id == image.id }
    }

    /// Triggers an iCloud download for a cloud-only file and updates its entry
    /// once the download completes.
    func downloadCloudFile(_ image: ImageFile) {
        guard image.isCloudOnly else { return }
        let url = image.url
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            print("Failed to start iCloud download: \(error)")
            return
        }

        Task.detached { [weak self] in
            // Poll until the file is downloaded (up to ~60 seconds)
            for _ in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                if !Self.isCloudOnlyFile(url) { break }
            }
            guard !Self.isCloudOnlyFile(url) else { return }

            // Re-read metadata now that the file is local
            let ext = url.pathExtension.lowercased()
            let isVideo = Self.videoExtensions.contains(ext)
            var pixelWidth = 0
            var pixelHeight = 0
            var isAnimated = false
            if !isVideo,
               let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                    pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                }
                isAnimated = CGImageSourceGetCount(source) > 1
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateImage(id: image.id, pixelWidth: pixelWidth, pixelHeight: pixelHeight, isAnimated: isAnimated)
            }
        }
    }

    /// Updates an image entry in both `images` and `tagFilteredImages` after download.
    private func updateImage(id: UUID, pixelWidth: Int, pixelHeight: Int, isAnimated: Bool) {
        if let idx = images.firstIndex(where: { $0.id == id }) {
            images[idx].isCloudOnly = false
            images[idx].pixelWidth = pixelWidth
            images[idx].pixelHeight = pixelHeight
            images[idx].isAnimated = isAnimated
        }
        if let idx = tagFilteredImages?.firstIndex(where: { $0.id == id }) {
            tagFilteredImages?[idx].isCloudOnly = false
            tagFilteredImages?[idx].pixelWidth = pixelWidth
            tagFilteredImages?[idx].pixelHeight = pixelHeight
            tagFilteredImages?[idx].isAnimated = isAnimated
        }
        lastDownloadedFileId = id
    }

    /// Recursively scans all files under a root URL, returning only those whose path is in matchingPaths.
    private static func scanAllFiles(under root: URL, matchingPaths: Set<String>) -> [ImageFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .creationDateKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [ImageFile] = []
        for case let fileURL as URL in enumerator {
            guard matchingPaths.contains(TagDatabase.hashPath(fileURL.path)) else { continue }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .creationDateKey, .contentModificationDateKey]),
                  resourceValues.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let isVideo = videoExtensions.contains(ext)
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let cloudOnly = isCloudOnlyFile(fileURL)
            var imageFile = ImageFile(
                url: fileURL,
                name: fileURL.lastPathComponent,
                fileSize: fileSize,
                createdDate: resourceValues.creationDate ?? .distantPast,
                modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
                isVideo: isVideo,
                isCloudOnly: cloudOnly
            )
            if !isVideo, !cloudOnly,
               let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
                if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    imageFile.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                    imageFile.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                }
                imageFile.isAnimated = CGImageSourceGetCount(source) > 1
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

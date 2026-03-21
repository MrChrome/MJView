//
//  ContentView.swift
//  MJView
//
//  Created by Marc Santa on 3/20/26.
//

import SwiftUI

struct ContentView: View {
    var appState: AppState
    @State private var loader = ImageLoader()
    @State private var tagDatabase = TagDatabase()
    @State private var selectedImage: ImageFile?
    @State private var selectedImages: Set<ImageFile> = []
    @State private var thumbnailSize: CGFloat = 80
    @State private var sidebarWidth: CGFloat = 220
    @State private var isTagPanelVisible = true
    @State private var eventMonitor: Any?
    @State private var renamingTagInFilter: Tag?
    @State private var lastSelectedIndex: Int = 0
    @State private var renameFilterText: String = ""
    @State private var fileTypeFilter: FileTypeFilter = .all
    @State private var showUntaggedOnly: Bool = false
    @State private var selectedTagIds: Set<Int64> = []
    @AppStorage("sortOrder") private var sortOrderRaw: String = SortOrder.name.rawValue
    private var sortOrder: SortOrder {
        get { SortOrder(rawValue: sortOrderRaw) ?? .name }
        nonmutating set { sortOrderRaw = newValue.rawValue }
    }

    private var sortedImages: [ImageFile] {
        let tagSource = loader.tagFilteredImages ?? loader.images
        var source: [ImageFile]
        switch fileTypeFilter {
        case .all:    source = tagSource
        case .images: source = tagSource.filter { !$0.isVideo }
        case .videos: source = tagSource.filter { $0.isVideo }
        }
        if showUntaggedOnly {
            source = source.filter { !tagDatabase.isPathTagged($0.url.path) }
        }
        switch sortOrder {
        case .oldest:           return source.sorted { $0.createdDate < $1.createdDate }
        case .newest:           return source.sorted { $0.createdDate > $1.createdDate }
        case .recentlyModified: return source.sorted { $0.modifiedDate > $1.modifiedDate }
        case .name:             return source.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:             return source.sorted { $0.fileSize > $1.fileSize }
        case .random:           return source
        case .type:             return source.sorted {
            let ext0 = $0.url.pathExtension.lowercased()
            let ext1 = $1.url.pathExtension.lowercased()
            if ext0 == ext1 { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ext0.localizedStandardCompare(ext1) == .orderedAscending
        }
        }
    }

    private var thumbnailGrid: some View {
        ThumbnailGridView(
            images: loader.images,
            subfolders: loader.subfolders,
            canGoUp: loader.canGoUp,
            selectedImage: $selectedImage,
            selectedImages: $selectedImages,
            thumbnailSize: $thumbnailSize,
            folderPath: loader.currentFolder?.path ?? "",
            onNavigateToSubfolder: { loader.navigateToSubfolder($0) },
            onNavigateUp: {
                loader.navigateUp()
                loader.clearTagFilter()
                selectedTagIds = []
                fileTypeFilter = .all
                showUntaggedOnly = false
            },
            sortOrder: Binding(get: { sortOrder }, set: { sortOrder = $0 }),
            allTags: loader.rootFolder.map { tagDatabase.tagsUsedUnderRoot($0.path) } ?? tagDatabase.allTags,
            tagFilteredImages: loader.tagFilteredImages,
            onTagFilterChanged: { tagIds in
                guard let root = loader.rootFolder else { return }
                let paths = tagDatabase.imagePaths(
                    matchingAllTagIds: Array(tagIds),
                    underFolder: root.path + "/"
                )
                loader.applyTagFilter(matchingPaths: paths)
            },
            onTagFilterCleared: {
                loader.clearTagFilter()
            },
            onRenameTag: { tag in
                renameFilterText = tag.name
                renamingTagInFilter = tag
            },
            fileTypeFilter: $fileTypeFilter,
            showUntaggedOnly: $showUntaggedOnly,
            taggedPaths: tagDatabase.allTaggedPaths,
            selectedTagIds: $selectedTagIds
        )
        .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 400)
    }

    var body: some View {
        HSplitView {
            // Sidebar with thumbnails
            thumbnailGrid

            // Main image view
            ImageDetailView(imageFile: selectedImage)
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

            // Tag panel
            if isTagPanelVisible {
                TagPanelView(
                    imageFiles: selectedImages.isEmpty
                        ? (selectedImage.map { [$0] } ?? [])
                        : selectedImages.sorted { $0.name < $1.name },
                    database: tagDatabase,
                    rootFolderPath: loader.rootFolder?.path
                )
                .frame(minWidth: 180, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    loader.needsFolderSelection = true
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Folder")

                Button {
                    if let url = selectedImage?.url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Reveal in Finder")
                .disabled(selectedImage == nil)

                Button {
                    isTagPanelVisible.toggle()
                } label: {
                    Image(systemName: "tag")
                }
                .help("Toggle Tags Panel")
            }
        }
        .sheet(isPresented: $loader.needsFolderSelection) {
            FolderPickerView(
                recentFolders: loader.recentFolders,
                onSelectFolder: { url in
                    loader.loadFolder(url, isRoot: true)
                },
                onBrowse: {
                    loader.needsFolderSelection = false
                    loader.chooseFolder()
                },
                onDismiss: {
                    loader.needsFolderSelection = false
                }
            )
            .padding(0)
        }
        .onChange(of: selectedImage) {
            appState.selectedImage = selectedImage
            if let current = selectedImage, let index = sortedImages.firstIndex(of: current) {
                lastSelectedIndex = index
            }
            // Auto-download cloud-only files when selected
            if let image = selectedImage, image.isCloudOnly {
                loader.downloadCloudFile(image)
            }
        }
        .onChange(of: loader.lastDownloadedFileId) {
            // When a cloud file finishes downloading, refresh the selected image
            // so the detail view picks up the updated isCloudOnly state.
            guard let downloadedId = loader.lastDownloadedFileId else { return }
            if let current = selectedImage, current.id == downloadedId,
               let updated = loader.images.first(where: { $0.id == downloadedId }) {
                selectedImage = updated
            }
            selectedImages = selectedImages.map { img in
                if img.id == downloadedId, let updated = loader.images.first(where: { $0.id == downloadedId }) {
                    return updated
                }
                return img
            }.reduce(into: Set<ImageFile>()) { $0.insert($1) }
        }
        .onChange(of: appState.deleteTrigger) {
            deleteSelected()
        }
        .onChange(of: loader.isLoading) {
            // When a folder finishes loading, select the first image.
            // Skip if we still have a valid selection (e.g. a cloud file just updated).
            guard !loader.isLoading else { return }
            if let current = selectedImage, loader.images.contains(where: { $0.url == current.url }) {
                return
            }
            selectedImages = []
            selectedImage = loader.images.isEmpty ? nil : sortedImages.first
            if let first = selectedImage { selectedImages = [first] }
        }
        .onChange(of: loader.rootFolder) {
            if let root = loader.rootFolder {
                tagDatabase.setRootFolder(root)
            } else {
                tagDatabase.currentRootPath = ""
            }
        }
        .onChange(of: tagDatabase.allTaggedPaths) {
            // When in untagged-only view, don't auto-advance when the current image gets
            // its first tag — the user may want to add more tags before moving on.
            // Auto-advance only happens via explicit arrow-key or click navigation.
        }
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 123 { // left arrow
                    selectPreviousImage()
                    return nil
                } else if event.keyCode == 124 { // right arrow
                    selectNextImage()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .alert("Rename Tag", isPresented: Binding(
            get: { renamingTagInFilter != nil },
            set: { if !$0 { renamingTagInFilter = nil } }
        )) {
            TextField("Tag name", text: $renameFilterText)
            Button("Rename") {
                if let tag = renamingTagInFilter {
                    tagDatabase.renameTag(tagId: tag.id, newName: renameFilterText)
                }
                renamingTagInFilter = nil
            }
            Button("Cancel", role: .cancel) {
                renamingTagInFilter = nil
            }
        }
    }

    private func deleteSelected() {
        guard let image = selectedImage else { return }
        let sorted = sortedImages
        if let index = sorted.firstIndex(of: image) {
            if index + 1 < sorted.count {
                selectedImage = sorted[index + 1]
            } else if index > 0 {
                selectedImage = sorted[index - 1]
            } else {
                selectedImage = nil
            }
        }
        do {
            try FileManager.default.removeItem(at: image.url)
        } catch {
            print("Delete failed: \(error)")
        }
        loader.removeImage(image)
    }

    private func selectPreviousImage() {
        guard !sortedImages.isEmpty else { return }
        if let current = selectedImage, let index = sortedImages.firstIndex(of: current) {
            // Current image is still in the list — move normally
            guard index > 0 else { return }
            let image = sortedImages[index - 1]
            selectedImage = image
            selectedImages = [image]
        } else {
            // Current image was filtered out — lastSelectedIndex now points to the
            // image that slid into that position, so go one before it
            let index = min(lastSelectedIndex, sortedImages.count - 1)
            guard index > 0 else { return }
            let image = sortedImages[index - 1]
            selectedImage = image
            selectedImages = [image]
        }
    }

    private func selectNextImage() {
        guard !sortedImages.isEmpty else { return }
        if let current = selectedImage, let index = sortedImages.firstIndex(of: current) {
            // Current image is still in the list — move normally
            guard index < sortedImages.count - 1 else { return }
            let image = sortedImages[index + 1]
            selectedImage = image
            selectedImages = [image]
        } else {
            // Current image was filtered out — lastSelectedIndex now points to the
            // image that slid into that position, so go there directly (not +1)
            let index = min(lastSelectedIndex, sortedImages.count - 1)
            let image = sortedImages[index]
            selectedImage = image
            selectedImages = [image]
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}

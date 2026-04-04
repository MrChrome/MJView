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
    @State private var isCropping: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var isFlippedHorizontal: Bool = false
    @State private var isFlippedVertical: Bool = false
    @State private var pendingSelectURL: URL?
    @State private var renamingTagInFilter: Tag?
    @State private var renamingImage: ImageFile?
    @State private var renameImageText: String = ""
    @State private var deletingImage: ImageFile?
    @State private var showingMultiDeleteConfirmation: Bool = false
    @State private var promptImage: ImageFile?
    @State private var promptText: String?
    @State private var lastSelectedIndex: Int = 0
    @State private var gridImages: [ImageFile] = []
    @State private var metadataVersion: Int = 0
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

    private var imageDetailView: some View {
        ImageDetailView(
            imageFile: selectedImage,
            metadataVersion: metadataVersion,
            isCropping: $isCropping,
            isScrubbing: $isScrubbing,
            isFlippedHorizontal: $isFlippedHorizontal,
            isFlippedVertical: $isFlippedVertical,
            onCropCompleted: { savedURL, mode in
                handleCropCompleted(savedURL: savedURL, mode: mode)
            },
            onFlipCompleted: { savedURL, mode in
                handleCropCompleted(savedURL: savedURL, mode: mode)
            }
        )
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canCrop: Bool {
        guard let img = selectedImage else { return false }
        return !img.isVideo && !img.isAnimated && !img.isCloudOnly
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
            onRenameImage: { image in
                renameImageText = image.name
                renamingImage = image
            },
            onDeleteImage: { image in
                deletingImage = image
            },
            onDeleteSelectedImages: {
                showingMultiDeleteConfirmation = true
            },
            onShowPrompt: { image in
                promptImage = image
                promptText = PromptReader.readPrompt(from: image.url)
            },
            fileTypeFilter: $fileTypeFilter,
            showUntaggedOnly: $showUntaggedOnly,
            taggedPaths: tagDatabase.allTaggedPaths,
            selectedTagIds: $selectedTagIds,
            sortedImagesForNav: $gridImages
        )
        .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 400)
        .overlay {
            if loader.isLoading {
                ZStack {
                    Color(nsColor: .controlBackgroundColor).opacity(0.85)
                    VStack(spacing: 8) {
                        ProgressView(value: loader.loadingProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                            .animation(.easeInOut(duration: 0.15), value: loader.loadingProgress)
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar with thumbnails
            thumbnailGrid

            // Main image view
            imageDetailView

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
                    isCropping.toggle()
                } label: {
                    Image(systemName: isCropping ? "crop.rotate" : "crop")
                }
                .help(isCropping ? "Cancel Crop" : "Crop Image")
                .disabled(!canCrop)

                Button {
                    isScrubbing.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.below.rectangle")
                }
                .help(isScrubbing ? "Hide Frame Scrubber" : "Show Frame Scrubber")
                .disabled(!(selectedImage?.isAnimated ?? false))

                Button {
                    isFlippedHorizontal.toggle()
                } label: {
                    Image(systemName: "flip.horizontal")
                }
                .help(isFlippedHorizontal ? "Reset Horizontal Flip" : "Flip Horizontally")
                .disabled(selectedImage == nil || selectedImage?.isVideo == true)

                Button {
                    isFlippedVertical.toggle()
                } label: {
                    Image(systemName: "flip.horizontal.fill")
                        .rotationEffect(.degrees(90))
                }
                .help(isFlippedVertical ? "Reset Vertical Flip" : "Flip Vertically")
                .disabled(selectedImage == nil || selectedImage?.isVideo == true)

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
            if let current = selectedImage, let index = gridImages.firstIndex(of: current) {
                lastSelectedIndex = index
            }
            // Hide scrubber when switching to a non-animated image
            if !(selectedImage?.isAnimated ?? false) {
                isScrubbing = false
            }
            // Auto-download cloud-only files when selected
            if let image = selectedImage, image.isCloudOnly {
                loader.downloadCloudFile(image)
            }
            // Lazily load pixel dimensions and animation state
            if let image = selectedImage {
                loader.loadMetadataIfNeeded(for: image)
            }
        }
        .onChange(of: loader.lastDownloadedFileId) {
            // When a file's metadata or download finishes, refresh stale copies
            // throughout the view so arrow-key navigation and the detail view
            // pick up the updated fields (pixelWidth, isAnimated, isCloudOnly).
            guard let downloadedId = loader.lastDownloadedFileId else { return }
            let updated = loader.images.first(where: { $0.id == downloadedId })
            // Keep gridImages in sync so arrow-key navigation uses fresh data.
            if let updated, let idx = gridImages.firstIndex(where: { $0.id == downloadedId }) {
                gridImages[idx] = updated
            }
            if let current = selectedImage, current.id == downloadedId, let updated {
                selectedImage = updated
                metadataVersion += 1
            }
            selectedImages = selectedImages.map { img in
                if img.id == downloadedId, let updated { return updated }
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
        .onChange(of: loader.currentFolder) {
            appState.currentFolderName = loader.currentFolder?.lastPathComponent ?? "MJView"
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
        .modifier(CropAndLifecycleModifier(
            isCropping: $isCropping,
            pendingSelectURL: $pendingSelectURL,
            selectedImage: $selectedImage,
            selectedImages: $selectedImages,
            loaderImages: loader.images,
            cropTrigger: appState.cropTrigger,
            onSelectPrevious: selectPreviousImage,
            onSelectNext: selectNextImage
        ))
        .modifier(RenameModifier(
            renamingTagInFilter: $renamingTagInFilter,
            renameFilterText: $renameFilterText,
            renamingImage: $renamingImage,
            renameImageText: $renameImageText,
            selectedImage: $selectedImage,
            selectedImages: $selectedImages,
            onRenameTag: { tag, newName in tagDatabase.renameTag(tagId: tag.id, newName: newName) },
            onRenameImage: { image, newName in
                loader.renameImage(image, newName: newName, tagDatabase: tagDatabase)
            }
        ))
        .alert("Delete \"\(deletingImage?.name ?? "")\"?",
               isPresented: Binding(
                get: { deletingImage != nil },
                set: { if !$0 { deletingImage = nil } }
               )) {
            Button("Delete", role: .destructive) {
                if let image = deletingImage {
                    deletingImage = nil
                    deleteImage(image)
                }
            }
            Button("Cancel", role: .cancel) {
                deletingImage = nil
            }
        } message: {
            Text("This will permanently delete the file from disk.")
        }
        .alert("Delete \(selectedImages.count) images?",
               isPresented: $showingMultiDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedImages()
            }
            Button("Cancel", role: .cancel) {
                showingMultiDeleteConfirmation = false
            }
        } message: {
            Text("This will permanently delete all selected files from disk.")
        }
        .sheet(isPresented: Binding(
            get: { promptImage != nil },
            set: { if !$0 { promptImage = nil; promptText = nil } }
        )) {
            PromptSheetView(
                fileName: promptImage?.name ?? "",
                prompt: promptText,
                onDismiss: { promptImage = nil; promptText = nil }
            )
        }
    }

    private func handleCropCompleted(savedURL: URL, mode: CropSaveMode) {
        switch mode {
        case .overwrite:
            // The detail view already increments reloadCounter to reload the image.
            // Nothing else needed here.
            break
        case .saveAsNew:
            // Store the URL; once the filesystem watcher picks up the new file and
            // adds it to loader.images, the onChange handler will auto-select it.
            pendingSelectURL = savedURL
        }
    }

    private func deleteSelected() {
        guard let image = selectedImage else { return }
        deleteImage(image)
    }

    private func deleteImage(_ image: ImageFile) {
        // Advance selection away from the deleted image if it is currently selected
        if selectedImage == image {
            let sorted = gridImages
            if let index = sorted.firstIndex(of: image) {
                if index + 1 < sorted.count {
                    selectedImage = sorted[index + 1]
                } else if index > 0 {
                    selectedImage = sorted[index - 1]
                } else {
                    selectedImage = nil
                }
            }
        }
        selectedImages.remove(image)
        do {
            try FileManager.default.removeItem(at: image.url)
        } catch {
            print("Delete failed: \(error)")
        }
        loader.removeImage(image)
    }

    private func deleteSelectedImages() {
        let imagesToDelete = selectedImages
        let sorted = gridImages

        // Find a new selection after deletion
        let remainingImages = sorted.filter { !imagesToDelete.contains($0) }
        if let current = selectedImage, imagesToDelete.contains(current) {
            if let index = sorted.firstIndex(of: current) {
                // Find the next image that's not being deleted
                var nextIndex = index + 1
                while nextIndex < sorted.count && imagesToDelete.contains(sorted[nextIndex]) {
                    nextIndex += 1
                }
                if nextIndex < sorted.count {
                    selectedImage = sorted[nextIndex]
                } else {
                    // No next image, find previous
                    var prevIndex = index - 1
                    while prevIndex >= 0 && imagesToDelete.contains(sorted[prevIndex]) {
                        prevIndex -= 1
                    }
                    if prevIndex >= 0 {
                        selectedImage = sorted[prevIndex]
                    } else {
                        selectedImage = nil
                    }
                }
            } else {
                selectedImage = remainingImages.first
            }
        }

        selectedImages = []

        for image in imagesToDelete {
            do {
                try FileManager.default.removeItem(at: image.url)
            } catch {
                print("Delete failed for \(image.name): \(error)")
            }
            loader.removeImage(image)
        }
    }

    private func selectPreviousImage() {
        guard !gridImages.isEmpty else { return }
        if let current = selectedImage, let index = gridImages.firstIndex(of: current) {
            // Current image is still in the list — wrap around to last if at the beginning
            let prevIndex = index > 0 ? index - 1 : gridImages.count - 1
            let image = gridImages[prevIndex]
            selectedImage = image
            selectedImages = [image]
        } else {
            // Current image was filtered out — lastSelectedIndex now points to the
            // image that slid into that position, so go one before it
            let index = min(lastSelectedIndex, gridImages.count - 1)
            let prevIndex = index > 0 ? index - 1 : gridImages.count - 1
            let image = gridImages[prevIndex]
            selectedImage = image
            selectedImages = [image]
        }
    }

    private func selectNextImage() {
        guard !gridImages.isEmpty else { return }
        if let current = selectedImage, let index = gridImages.firstIndex(of: current) {
            // Current image is still in the list — wrap around to first if at the end
            let nextIndex = index < gridImages.count - 1 ? index + 1 : 0
            let image = gridImages[nextIndex]
            selectedImage = image
            selectedImages = [image]
        } else {
            // Current image was filtered out — lastSelectedIndex now points to the
            // image that slid into that position, so go there directly (not +1)
            let index = min(lastSelectedIndex, gridImages.count - 1)
            let image = gridImages[index]
            selectedImage = image
            selectedImages = [image]
        }
    }
}

// MARK: - View Modifiers extracted to keep ContentView.body type-checkable

private struct CropAndLifecycleModifier: ViewModifier {
    @Binding var isCropping: Bool
    @Binding var pendingSelectURL: URL?
    @Binding var selectedImage: ImageFile?
    @Binding var selectedImages: Set<ImageFile>
    let loaderImages: [ImageFile]
    let cropTrigger: Int
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void

    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: loaderImages) {
                guard let pending = pendingSelectURL,
                      let newImage = loaderImages.first(where: { $0.url == pending }) else { return }
                selectedImage = newImage
                selectedImages = [newImage]
                pendingSelectURL = nil
            }
            .onChange(of: cropTrigger) {
                guard let img = selectedImage,
                      !img.isVideo, !img.isAnimated, !img.isCloudOnly else { return }
                isCropping.toggle()
            }
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if isCropping {
                        if event.keyCode == 53 { // Escape
                            isCropping = false
                            return nil
                        }
                        return event // block other navigation while cropping
                    }
                    if event.keyCode == 123 { // left arrow
                        onSelectPrevious()
                        return nil
                    } else if event.keyCode == 124 { // right arrow
                        onSelectNext()
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
    }
}

private struct RenameModifier: ViewModifier {
    @Binding var renamingTagInFilter: Tag?
    @Binding var renameFilterText: String
    @Binding var renamingImage: ImageFile?
    @Binding var renameImageText: String
    @Binding var selectedImage: ImageFile?
    @Binding var selectedImages: Set<ImageFile>
    let onRenameTag: (Tag, String) -> Void
    let onRenameImage: (ImageFile, String) -> ImageFile?

    func body(content: Content) -> some View {
        content
            .alert("Rename Tag", isPresented: Binding(
                get: { renamingTagInFilter != nil },
                set: { if !$0 { renamingTagInFilter = nil } }
            )) {
                TextField("Tag name", text: $renameFilterText)
                Button("Rename") {
                    if let tag = renamingTagInFilter {
                        onRenameTag(tag, renameFilterText)
                    }
                    renamingTagInFilter = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingTagInFilter = nil
                }
            }
            .alert("Rename File", isPresented: Binding(
                get: { renamingImage != nil },
                set: { if !$0 { renamingImage = nil } }
            )) {
                TextField("File name", text: $renameImageText)
                Button("Rename") {
                    if let image = renamingImage {
                        if let updated = onRenameImage(image, renameImageText) {
                            if selectedImage == image { selectedImage = updated }
                            if selectedImages.contains(image) {
                                selectedImages.remove(image)
                                selectedImages.insert(updated)
                            }
                        }
                    }
                    renamingImage = nil
                }
                Button("Cancel", role: .cancel) {
                    renamingImage = nil
                }
            }
    }
}

#Preview {
    ContentView(appState: AppState())
}

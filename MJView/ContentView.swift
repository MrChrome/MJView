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
    @State private var renameFilterText: String = ""
    @State private var fileTypeFilter: FileTypeFilter = .all
    @State private var showUntaggedOnly: Bool = false
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

    var body: some View {
        HSplitView {
            // Sidebar with thumbnails
            ThumbnailGridView(
                images: loader.images,
                subfolders: loader.subfolders,
                canGoUp: loader.canGoUp,
                selectedImage: $selectedImage,
                selectedImages: $selectedImages,
                thumbnailSize: $thumbnailSize,
                folderPath: loader.currentFolder?.path ?? "",
                onNavigateToSubfolder: { loader.navigateToSubfolder($0) },
                onNavigateUp: { loader.navigateUp() },
                sortOrder: Binding(get: { sortOrder }, set: { sortOrder = $0 }),
                allTags: tagDatabase.allTags,
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
                taggedPaths: tagDatabase.allTaggedPaths
            )
            .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 400)

            // Main image view
            ImageDetailView(imageFile: selectedImage)
                .frame(minWidth: 300)

            // Tag panel
            if isTagPanelVisible {
                TagPanelView(
                    imageFiles: selectedImages.isEmpty
                        ? (selectedImage.map { [$0] } ?? [])
                        : selectedImages.sorted { $0.name < $1.name },
                    database: tagDatabase,
                    rootFolderPath: loader.rootFolder?.path
                )
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
        }
        .onChange(of: appState.deleteTrigger) {
            deleteSelected()
        }
        .onChange(of: loader.images) {
            // Select the first file (not folder) in sorted order when a folder loads
            selectedImages = []
            selectedImage = loader.images.isEmpty ? nil : sortedImages.first
            if let first = selectedImage { selectedImages = [first] }
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
        print("deleteSelected called, selectedImage: \(selectedImage?.url.lastPathComponent ?? "nil")")
        print("accessedURL: \(loader.accessedURL?.path ?? "nil")")
        guard let image = selectedImage else { return }
        let sorted = sortedImages
        // Advance to next, then previous, before deleting
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
            print("Deleted: \(image.url.path)")
        } catch {
            print("Delete failed: \(error)")
        }
        loader.removeImage(image)
    }

    private func selectPreviousImage() {
        guard let current = selectedImage,
              let index = sortedImages.firstIndex(of: current),
              index > 0 else { return }
        let image = sortedImages[index - 1]
        selectedImage = image
        selectedImages = [image]
    }

    private func selectNextImage() {
        guard let current = selectedImage,
              let index = sortedImages.firstIndex(of: current),
              index < sortedImages.count - 1 else { return }
        let image = sortedImages[index + 1]
        selectedImage = image
        selectedImages = [image]
    }
}

#Preview {
    ContentView(appState: AppState())
}

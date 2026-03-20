//
//  ContentView.swift
//  MJView
//
//  Created by Marc Santa on 3/20/26.
//

import SwiftUI

struct ContentView: View {
    @State private var loader = ImageLoader()
    @State private var tagDatabase = TagDatabase()
    @State private var selectedImage: ImageFile?
    @State private var thumbnailSize: CGFloat = 80
    @State private var sidebarWidth: CGFloat = 220
    @State private var isTagPanelVisible = true
    @AppStorage("sortOrder") private var sortOrderRaw: String = SortOrder.name.rawValue
    private var sortOrder: SortOrder {
        get { SortOrder(rawValue: sortOrderRaw) ?? .name }
        nonmutating set { sortOrderRaw = newValue.rawValue }
    }

    private var sortedImages: [ImageFile] {
        let source = loader.tagFilteredImages ?? loader.images
        switch sortOrder {
        case .oldest:           return source.sorted { $0.createdDate < $1.createdDate }
        case .newest:           return source.sorted { $0.createdDate > $1.createdDate }
        case .recentlyModified: return source.sorted { $0.modifiedDate > $1.modifiedDate }
        case .name:             return source.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:             return source.sorted { $0.fileSize > $1.fileSize }
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
                }
            )
            .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 400)

            // Main image view
            ImageDetailView(imageFile: selectedImage)
                .frame(minWidth: 300)

            // Tag panel
            if isTagPanelVisible {
                TagPanelView(imageFile: selectedImage, database: tagDatabase)
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
        .onChange(of: loader.images) {
            // Select the first file (not folder) in sorted order when a folder loads
            selectedImage = loader.images.isEmpty ? nil : sortedImages.first
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
    }

    private func selectPreviousImage() {
        guard let current = selectedImage,
              let index = sortedImages.firstIndex(of: current),
              index > 0 else { return }
        selectedImage = sortedImages[index - 1]
    }

    private func selectNextImage() {
        guard let current = selectedImage,
              let index = sortedImages.firstIndex(of: current),
              index < sortedImages.count - 1 else { return }
        selectedImage = sortedImages[index + 1]
    }
}

#Preview {
    ContentView()
}

//
//  ThumbnailGridView.swift
//  MJView
//

import SwiftUI

enum SortOrder: String, CaseIterable {
    case oldest = "Oldest"
    case newest = "Newest"
    case recentlyModified = "Recently Modified"
    case name = "Name"
    case size = "Size"
    case type = "Type"
    case random = "Random"

    var systemImage: String {
        switch self {
        case .oldest:           return "calendar.badge.minus"
        case .newest:           return "calendar.badge.plus"
        case .recentlyModified: return "clock.arrow.circlepath"
        case .name:             return "textformat.abc"
        case .size:             return "externaldrive"
        case .type:             return "doc.on.doc"
        case .random:           return "shuffle"
        }
    }
}

struct ThumbnailGridView: View {
    let images: [ImageFile]
    let subfolders: [FolderItem]
    let canGoUp: Bool
    @Binding var selectedImage: ImageFile?
    @Binding var selectedImages: Set<ImageFile>
    @Binding var thumbnailSize: CGFloat
    let folderPath: String
    var onNavigateToSubfolder: (URL) -> Void = { _ in }
    var onNavigateUp: () -> Void = {}

    @Binding var sortOrder: SortOrder

    // Tag filtering
    let allTags: [Tag]
    let tagFilteredImages: [ImageFile]?
    let onTagFilterChanged: (Set<Int64>) -> Void
    let onTagFilterCleared: () -> Void

    @State private var selectedTagIds: Set<Int64> = []
    @State private var isFilterPopoverShown = false
    @State private var shuffleSeed: UInt64 = 0

    // Unified item for the grid so folders and images can be interleaved
    enum TileItem: Identifiable {
        case folder(FolderItem)
        case image(ImageFile)

        var id: String {
            switch self {
            case .folder(let f): return "f:" + f.url.path
            case .image(let img): return "i:" + img.url.path
            }
        }

        var sortName: String {
            switch self {
            case .folder(let f): return f.name
            case .image(let img): return img.name
            }
        }

        var createdDate: Date {
            switch self {
            case .folder(let f): return f.createdDate
            case .image(let img): return img.createdDate
            }
        }

        var modifiedDate: Date {
            switch self {
            case .folder(let f): return f.modifiedDate
            case .image(let img): return img.modifiedDate
            }
        }
    }

    var sortedItems: [TileItem] {
        // When a tag filter is active, show only matching files (no subfolders)
        let sourceImages = tagFilteredImages ?? images
        let folderItems = tagFilteredImages == nil ? subfolders.map { TileItem.folder($0) } : []
        let imageItems = sourceImages.map { TileItem.image($0) }
        let combined = folderItems + imageItems

        switch sortOrder {
        case .name:
            return combined.sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
        case .type:
            return combined.sorted {
                let ext0: String
                let ext1: String
                switch $0 { case .folder: ext0 = ""; case .image(let i): ext0 = i.url.pathExtension.lowercased() }
                switch $1 { case .folder: ext1 = ""; case .image(let i): ext1 = i.url.pathExtension.lowercased() }
                if ext0 == ext1 { return $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
                return ext0.localizedStandardCompare(ext1) == .orderedAscending
            }
        case .oldest:
            return combined.sorted { $0.createdDate < $1.createdDate }
        case .newest:
            return combined.sorted { $0.createdDate > $1.createdDate }
        case .recentlyModified:
            return combined.sorted { $0.modifiedDate > $1.modifiedDate }
        case .size:
            return combined.sorted {
                let s0: Int64
                let s1: Int64
                switch $0 { case .folder: s0 = 0; case .image(let i): s0 = i.fileSize }
                switch $1 { case .folder: s1 = 0; case .image(let i): s1 = i.fileSize }
                return s0 > s1
            }
        case .random:
            var rng = SeededRandomNumberGenerator(seed: shuffleSeed)
            return combined.shuffled(using: &rng)
        }
    }

    // Used by ContentView for arrow-key navigation
    var sortedImages: [ImageFile] {
        sortedItems.compactMap { if case .image(let img) = $0 { return img } else { return nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Folder path header
            HStack {
                // Up one folder button
                if canGoUp && tagFilteredImages == nil {
                    Button {
                        onNavigateUp()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Up One Folder")
                }

                Spacer()

                // Sort menu
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            if order == .random {
                                // Always re-shuffle when Random is picked
                                shuffleSeed = UInt64.random(in: 0...UInt64.max)
                            }
                            sortOrder = order
                        } label: {
                            Label(order.rawValue, systemImage: order.systemImage)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: sortOrder.systemImage)
                        Text(sortOrder.rawValue)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Tag filter button
                Button {
                    isFilterPopoverShown.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tagFilteredImages != nil ? "tag.fill" : "tag")
                            .foregroundStyle(tagFilteredImages != nil ? .blue : .secondary)
                        if tagFilteredImages != nil {
                            Text("\(selectedTagIds.count)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isFilterPopoverShown, arrowEdge: .bottom) {
                    TagFilterView(
                        allTags: allTags,
                        selectedTagIds: $selectedTagIds,
                        onApply: {
                            if selectedTagIds.isEmpty {
                                onTagFilterCleared()
                            } else {
                                onTagFilterChanged(selectedTagIds)
                            }
                        },
                        onClear: {
                            selectedTagIds = []
                            onTagFilterCleared()
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Thumbnail grid
            ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize), spacing: 4)],
                    spacing: 4
                ) {
                    // Folders and images interleaved by sort order
                    ForEach(sortedItems) { (item: TileItem) in
                        switch item {
                        case .folder(let folder):
                            FolderTileView(name: folder.name, size: thumbnailSize)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedImages = []
                                    onNavigateToSubfolder(folder.url)
                                }
                        case .image(let imageFile):
                            ThumbnailView(
                                imageFile: imageFile,
                                isSelected: selectedImages.contains(imageFile),
                                size: thumbnailSize
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                                if modifiers.contains(.command) {
                                    // Cmd+click: toggle this item in the selection
                                    if selectedImages.contains(imageFile) {
                                        selectedImages.remove(imageFile)
                                        if selectedImage == imageFile {
                                            selectedImage = selectedImages.first
                                        }
                                    } else {
                                        selectedImages.insert(imageFile)
                                        selectedImage = imageFile
                                    }
                                } else if modifiers.contains(.shift), let anchor = selectedImage {
                                    // Shift+click: select range from anchor to this item
                                    let imgs = sortedImages
                                    if let anchorIdx = imgs.firstIndex(of: anchor),
                                       let targetIdx = imgs.firstIndex(of: imageFile) {
                                        let range = anchorIdx <= targetIdx
                                            ? imgs[anchorIdx...targetIdx]
                                            : imgs[targetIdx...anchorIdx]
                                        selectedImages = Set(range)
                                        selectedImage = imageFile
                                    }
                                } else {
                                    // Plain click: single select
                                    selectedImages = [imageFile]
                                    selectedImage = imageFile
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
            .onChange(of: selectedImage) {
                if let id = selectedImage.map({ "i:" + $0.url.path }) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            } // ScrollViewReader

            Divider()

            // Thumbnail size slider
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $thumbnailSize, in: 40...200)
                    .controlSize(.mini)
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

struct FolderTileView: View {
    let name: String
    let size: CGFloat
    var showBackChevron: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.35))
                .foregroundStyle(.blue)
            HStack(spacing: 2) {
                if showBackChevron {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8))
                }
                Text(name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: size, height: size)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// A deterministic RNG seeded with a UInt64, used for stable random sort order.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

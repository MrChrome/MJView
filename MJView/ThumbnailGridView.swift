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

    var systemImage: String {
        switch self {
        case .oldest:         return "calendar.badge.minus"
        case .newest:         return "calendar.badge.plus"
        case .recentlyModified: return "clock.arrow.circlepath"
        case .name:           return "textformat.abc"
        case .size:           return "externaldrive"
        case .type:           return "doc.on.doc"
        }
    }
}

struct ThumbnailGridView: View {
    let images: [ImageFile]
    let subfolders: [URL]
    let canGoUp: Bool
    @Binding var selectedImage: ImageFile?
    @Binding var thumbnailSize: CGFloat
    let folderPath: String
    var onNavigateToSubfolder: (URL) -> Void = { _ in }
    var onNavigateUp: () -> Void = {}

    @Binding var sortOrder: SortOrder

    var sortedImages: [ImageFile] {
        switch sortOrder {
        case .oldest:           return images.sorted { $0.createdDate < $1.createdDate }
        case .newest:           return images.sorted { $0.createdDate > $1.createdDate }
        case .recentlyModified: return images.sorted { $0.modifiedDate > $1.modifiedDate }
        case .name:             return images.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:             return images.sorted { $0.fileSize > $1.fileSize }
        case .type:             return images.sorted {
            let ext0 = $0.url.pathExtension.lowercased()
            let ext1 = $1.url.pathExtension.lowercased()
            if ext0 == ext1 { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ext0.localizedStandardCompare(ext1) == .orderedAscending
        }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Folder path header
            HStack {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
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

                Spacer()

                Text(folderPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Thumbnail grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize), spacing: 4)],
                    spacing: 4
                ) {
                    // Back folder tile
                    if canGoUp {
                        FolderTileView(name: "..", size: thumbnailSize, showBackChevron: true)
                            .onTapGesture { onNavigateUp() }
                    }

                    // Subfolder tiles
                    ForEach(subfolders, id: \.self) { folder in
                        FolderTileView(name: folder.lastPathComponent, size: thumbnailSize)
                            .onTapGesture { onNavigateToSubfolder(folder) }
                    }

                    // Image thumbnails
                    ForEach(sortedImages) { imageFile in
                        ThumbnailView(
                            imageFile: imageFile,
                            isSelected: selectedImage == imageFile,
                            size: thumbnailSize
                        )
                        .onTapGesture {
                            selectedImage = imageFile
                        }
                    }
                }
                .padding(4)
            }

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

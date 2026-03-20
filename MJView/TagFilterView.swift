//
//  TagFilterView.swift
//  MJView
//

import SwiftUI

enum FileTypeFilter: String, CaseIterable {
    case all = "All"
    case images = "Images"
    case videos = "Videos"
}

struct TagFilterView: View {
    let allTags: [Tag]
    @Binding var selectedTagIds: Set<Int64>
    @Binding var fileTypeFilter: FileTypeFilter
    let onApply: () -> Void
    let onClear: () -> Void
    var onRenameTag: ((Tag) -> Void)?

    private var hasActiveFilters: Bool {
        !selectedTagIds.isEmpty || fileTypeFilter != .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Filter")
                    .font(.headline)
                Spacer()
                if hasActiveFilters {
                    Button("Clear All") {
                        fileTypeFilter = .all
                        onClear()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // File type filter
            VStack(alignment: .leading, spacing: 6) {
                Text("File Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(FileTypeFilter.allCases, id: \.self) { type in
                        let isSelected = fileTypeFilter == type
                        Button {
                            fileTypeFilter = type
                            onApply()
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
                                .foregroundStyle(isSelected ? .blue : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tags section header
            HStack {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if allTags.isEmpty {
                Text("No tags yet")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(allTags) { tag in
                            let isSelected = selectedTagIds.contains(tag.id)
                            Button {
                                if isSelected {
                                    selectedTagIds.remove(tag.id)
                                } else {
                                    selectedTagIds.insert(tag.id)
                                }
                                onApply()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .secondary)
                                        .font(.system(size: 14))
                                    Text(tag.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .background(isSelected ? Color.blue.opacity(0.08) : .clear)
                            .contextMenu {
                                Button("Rename…") {
                                    onRenameTag?(tag)
                                }
                            }

                            if tag.id != allTags.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 220)
    }
}

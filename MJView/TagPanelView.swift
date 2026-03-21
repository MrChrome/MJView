//
//  TagPanelView.swift
//  MJView
//

import SwiftUI

struct TagPanelView: View {
    let imageFiles: [ImageFile]
    var database: TagDatabase
    var rootFolderPath: String?

    @State private var newTagName: String = ""
    @State private var renamingTag: Tag?
    @State private var renameText: String = ""

    // The primary image (last clicked) used for displaying current tags
    private var primaryImage: ImageFile? { imageFiles.last }
    private var isMultiSelect: Bool { imageFiles.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tags")
                    .font(.headline)
                Spacer()
                if isMultiSelect {
                    Text("\(imageFiles.count) selected")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .clipShape(Capsule())
                } else if !database.tagsForCurrentImage.isEmpty {
                    Text("\(database.tagsForCurrentImage.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if primaryImage != nil {
                // Add tag input — applies to all selected images
                HStack(spacing: 4) {
                    TextField(isMultiSelect ? "Add tag to all..." : "Add tag...", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { addCurrentTag() }
                    Button {
                        addCurrentTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Applied tags — pinned, does not scroll
                if isMultiSelect {
                    Text("Tags on last selected:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }

                ForEach(database.tagsForCurrentImage) { tag in
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 10))
                        Text(tag.name)
                            .font(.system(size: 12))
                        Spacer()
                        Button {
                            for file in imageFiles {
                                database.removeTag(tagId: tag.id, fromImagePath: file.url.path)
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Rename…") {
                            renameText = tag.name
                            renamingTag = tag
                        }
                    }
                }

                // Quick-add section — scrollable
                let scopedTags: [Tag] = {
                    let source = rootFolderPath.map { database.tagsUsedUnderRoot($0) } ?? database.allTags
                    return source.filter { tag in
                        !database.tagsForCurrentImage.contains(where: { $0.id == tag.id })
                    }
                }()
                if !scopedTags.isEmpty {
                    Divider()
                        .padding(.top, 4)
                    Text("Tags in This Folder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(scopedTags) { tag in
                                Button {
                                    for file in imageFiles {
                                        database.addTag(name: tag.name, toImagePath: file.url.path)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 10))
                                        Text(tag.name)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename…") {
                                        renameText = tag.name
                                        renamingTag = tag
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select an image\nto manage tags")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
        .alert("Rename Tag", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("Tag name", text: $renameText)
            Button("Rename") {
                if let tag = renamingTag {
                    database.renameTag(tagId: tag.id, newName: renameText)
                    if let primary = primaryImage {
                        database.loadTags(forImagePath: primary.url.path)
                    }
                }
                renamingTag = nil
            }
            Button("Cancel", role: .cancel) {
                renamingTag = nil
            }
        }
        .onChange(of: primaryImage) {
            if let primary = primaryImage {
                database.loadTags(forImagePath: primary.url.path)
            } else {
                database.tagsForCurrentImage = []
            }
        }
    }

    private func addCurrentTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        for file in imageFiles {
            database.addTag(name: name, toImagePath: file.url.path)
        }
        newTagName = ""
    }
}

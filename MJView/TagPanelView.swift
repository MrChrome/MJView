//
//  TagPanelView.swift
//  MJView
//

import SwiftUI

struct TagPanelView: View {
    let imageFile: ImageFile?
    var database: TagDatabase

    @State private var newTagName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tags")
                    .font(.headline)
                Spacer()
                if !database.tagsForCurrentImage.isEmpty {
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

            if let imageFile {
                // Add tag input
                HStack(spacing: 4) {
                    TextField("Add tag...", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { addCurrentTag(to: imageFile) }
                    Button {
                        addCurrentTag(to: imageFile)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Current image tags
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(database.tagsForCurrentImage) { tag in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 10))
                                Text(tag.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Button {
                                    database.removeTag(tagId: tag.id, fromImagePath: imageFile.url.path)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }

                        // Quick-add from existing tags
                        let unusedTags = database.allTags.filter { tag in
                            !database.tagsForCurrentImage.contains(where: { $0.id == tag.id })
                        }
                        if !unusedTags.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                            Text("All Tags")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 2)
                            ForEach(unusedTags) { tag in
                                Button {
                                    database.addTag(name: tag.name, toImagePath: imageFile.url.path)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 10))
                                        Text(tag.name)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
        .onChange(of: imageFile) {
            if let imageFile {
                database.loadTags(forImagePath: imageFile.url.path)
            } else {
                database.tagsForCurrentImage = []
            }
        }
    }

    private func addCurrentTag(to imageFile: ImageFile) {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        database.addTag(name: name, toImagePath: imageFile.url.path)
        newTagName = ""
    }
}

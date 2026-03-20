//
//  TagFilterView.swift
//  MJView
//

import SwiftUI

struct TagFilterView: View {
    let allTags: [Tag]
    @Binding var selectedTagIds: Set<Int64>
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Filter by Tags")
                    .font(.headline)
                Spacer()
                if !selectedTagIds.isEmpty {
                    Button("Clear", action: onClear)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

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

//
//  CropSaveSheet.swift
//  MJView
//

import SwiftUI

struct CropSaveSheet: View {
    let originalFileName: String
    let newFileName: String
    let onSave: (CropSaveMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Save Cropped Image")
                .font(.headline)

            Text("How would you like to save the cropped image?")
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                saveButton(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Replace Original",
                    subtitle: originalFileName,
                    mode: .overwrite
                )
                saveButton(
                    icon: "doc.badge.plus",
                    title: "Save as New File",
                    subtitle: newFileName,
                    mode: .saveAsNew
                )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    @ViewBuilder
    private func saveButton(icon: String, title: String, subtitle: String, mode: CropSaveMode) -> some View {
        Button {
            onSave(mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

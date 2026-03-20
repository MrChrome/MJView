//
//  ImageDetailView.swift
//  MJView
//

import SwiftUI
import AppKit

struct ImageDetailView: View {
    let imageFile: ImageFile?

    @State private var nsImage: NSImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let imageFile {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)

                        if let nsImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(8)
                        } else {
                            ProgressView()
                        }
                    }
                    .task(id: imageFile.url) {
                        nsImage = nil
                        scale = 1.0
                        nsImage = await loadFullImage(url: imageFile.url)
                    }
                } else {
                    Color(nsColor: .controlBackgroundColor)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text("Select an image to preview")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }

            // Status bar
            if let imageFile {
                Divider()
                HStack(spacing: 16) {
                    Text(imageFile.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !imageFile.dimensionString.isEmpty {
                        Text(imageFile.dimensionString)
                            .foregroundStyle(.secondary)
                    }
                    Text(imageFile.fileSizeString)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.bar)
            }
        }
    }

    private func loadFullImage(url: URL) async -> NSImage? {
        return await Task.detached {
            NSImage(contentsOf: url)
        }.value
    }
}

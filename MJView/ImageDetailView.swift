//
//  ImageDetailView.swift
//  MJView
//

import SwiftUI
import AppKit
import AVKit

struct ImageDetailView: View {
    let imageFile: ImageFile?

    @State private var nsImage: NSImage?
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let imageFile {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)

                        if imageFile.isVideo {
                            if let player {
                                VideoPlayer(player: player)
                            } else {
                                ProgressView()
                            }
                        } else {
                            if let nsImage {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(8)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    .task(id: imageFile.url) {
                        nsImage = nil
                        player?.pause()
                        player = nil
                        if imageFile.isVideo {
                            player = AVPlayer(url: imageFile.url)
                        } else {
                            nsImage = await loadFullImage(url: imageFile.url)
                        }
                    }
                } else {
                    Color(nsColor: .controlBackgroundColor)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text("Select a file to preview")
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

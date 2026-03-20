//
//  ImageDetailView.swift
//  MJView
//

import SwiftUI
import AppKit
import AVKit

/// Wraps AVPlayerView in an NSViewRepresentable to avoid _AVKit_SwiftUI
/// type metadata crashes that can occur with the SwiftUI VideoPlayer.
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

/// Wraps NSImageView so animated WebP/GIF images play automatically.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        // Prevent the view from driving its parent's size
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
    }
}

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

                        if imageFile.isCloudOnly {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Downloading from iCloud…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if imageFile.isVideo {
                            if let player {
                                VideoPlayerView(player: player)
                            } else {
                                ProgressView()
                            }
                        } else {
                            if let nsImage {
                                if imageFile.isAnimated {
                                    AnimatedImageView(image: nsImage)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .aspectRatio(
                                            nsImage.size.width / max(nsImage.size.height, 1),
                                            contentMode: .fit
                                        )
                                        .padding(8)
                                        .onDrag {
                                            NSItemProvider(contentsOf: imageFile.url) ?? NSItemProvider()
                                        }
                                } else {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .padding(8)
                                        .onDrag {
                                            NSItemProvider(contentsOf: imageFile.url) ?? NSItemProvider()
                                        }
                                }
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    .task(id: "\(imageFile.url.path)|\(imageFile.isCloudOnly)") {
                        nsImage = nil
                        player?.pause()
                        player = nil
                        guard !imageFile.isCloudOnly else { return }
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
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }.value
    }
}

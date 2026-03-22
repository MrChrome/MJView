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
    @Binding var isCropping: Bool
    var onCropCompleted: ((URL, CropSaveMode) -> Void)?

    @State private var nsImage: NSImage?
    @State private var player: AVPlayer?
    @State private var reloadCounter: Int = 0
    @State private var showCropSaveSheet: Bool = false
    @State private var pendingNormalizedRect: CGRect?
    @State private var cropError: String?

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
                                    // Use GeometryReader so we can compute the rendered image rect
                                    // and position the crop overlay precisely over it.
                                    GeometryReader { geometry in
                                        let renderedRect = renderedImageRect(
                                            imageSize: nsImage.size,
                                            containerSize: geometry.size,
                                            padding: 8
                                        )

                                        // ZStack fills the GeometryReader so the Image centers
                                        // within it — matching what renderedImageRect computes.
                                        ZStack {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .padding(8)
                                                .onDrag {
                                                    NSItemProvider(contentsOf: imageFile.url) ?? NSItemProvider()
                                                }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                        if isCropping {
                                            CropOverlayView(
                                                imageSizeInView: renderedRect.size,
                                                imageOriginInView: renderedRect.origin,
                                                onCancel: {
                                                    isCropping = false
                                                },
                                                onApply: { normalizedRect in
                                                    pendingNormalizedRect = normalizedRect
                                                    showCropSaveSheet = true
                                                }
                                            )
                                        }
                                    }
                                }
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    .task(id: "\(imageFile.url.path)|\(imageFile.isCloudOnly)|\(reloadCounter)") {
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
                    .onChange(of: imageFile) {
                        // Exit crop mode when the selected image changes
                        isCropping = false
                    }
                    .sheet(isPresented: $showCropSaveSheet) {
                        CropSaveSheet(
                            originalFileName: imageFile.name,
                            newFileName: CropService.uniqueURL(for: imageFile.url).lastPathComponent,
                            onSave: { mode in
                                performCrop(imageFile: imageFile, mode: mode)
                                showCropSaveSheet = false
                                isCropping = false
                            },
                            onCancel: {
                                showCropSaveSheet = false
                            }
                        )
                    }
                    .alert("Crop Error", isPresented: Binding(
                        get: { cropError != nil },
                        set: { if !$0 { cropError = nil } }
                    )) {
                        Button("OK") { cropError = nil }
                    } message: {
                        Text(cropError ?? "")
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

    // MARK: - Crop helpers

    private func performCrop(imageFile: ImageFile, mode: CropSaveMode) {
        guard let normalizedRect = pendingNormalizedRect else { return }
        do {
            let savedURL = try CropService.cropAndSave(
                sourceURL: imageFile.url,
                normalizedRect: normalizedRect,
                saveMode: mode
            )
            if mode == .overwrite {
                // Force the image to reload by incrementing the reload counter
                reloadCounter += 1
            }
            onCropCompleted?(savedURL, mode)
        } catch {
            cropError = error.localizedDescription
        }
    }

    /// Computes the rect (in GeometryReader-local coordinates) occupied by the image
    /// when displayed with `.fit` aspect ratio, centered, with uniform padding.
    /// The image must be inside a container that fills the GeometryReader so it
    /// is truly centered — matching this calculation.
    private func renderedImageRect(imageSize: CGSize, containerSize: CGSize, padding: CGFloat) -> CGRect {
        let paddedWidth  = containerSize.width  - padding * 2
        let paddedHeight = containerSize.height - padding * 2
        guard paddedWidth > 0, paddedHeight > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: CGPoint(x: padding, y: padding),
                          size: CGSize(width: paddedWidth, height: paddedHeight))
        }

        let imageAspect     = imageSize.width  / imageSize.height
        let containerAspect = paddedWidth / paddedHeight

        let renderedSize: CGSize
        if imageAspect > containerAspect {
            // Width-limited: image fills the width, letterboxed vertically
            renderedSize = CGSize(width: paddedWidth, height: paddedWidth / imageAspect)
        } else {
            // Height-limited: image fills the height, pillarboxed horizontally
            renderedSize = CGSize(width: paddedHeight * imageAspect, height: paddedHeight)
        }

        let originX = padding + (paddedWidth  - renderedSize.width)  / 2
        let originY = padding + (paddedHeight - renderedSize.height) / 2

        return CGRect(origin: CGPoint(x: originX, y: originY), size: renderedSize)
    }

    private func loadFullImage(url: URL) async -> NSImage? {
        return await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }.value
    }
}

//
//  ImageDetailView.swift
//  MJView
//

import SwiftUI
import AppKit
import AVKit
import ImageIO

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

/// Drives frame-by-frame animation for animated WebP (and any format where
/// NSImageView.animates doesn't work) using CGImageSource frame data and a Timer.
@Observable
final class FrameAnimator {
    var currentImage: NSImage?

    private var frames: [(image: CGImage, delay: TimeInterval)] = []
    private var frameIndex = 0
    private var timer: Timer?

    func load(url: URL) {
        stop()
        frames = []
        frameIndex = 0
        currentImage = nil

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(source)

        // Build frame list, reading per-frame delay from WebP, GIF, or APNG metadata.
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let delay = Self.frameDelay(source: source, index: i)
            frames.append((cgImage, delay))
        }

        // If only one frame was decoded, try iterating via the WebP frame info array
        // (some WebP sources report count=1 but contain multiple frames).
        if frames.count <= 1,
           let containerProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let webpDict = containerProps[kCGImagePropertyWebPDictionary] as? [CFString: Any],
           let frameInfoArray = webpDict[kCGImagePropertyWebPFrameInfoArray] as? [[CFString: Any]],
           frameInfoArray.count > 1 {
            // Re-read using CGImageSourceCreateThumbnailAtIndex with full decode to get each frame
            frames = []
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: false,
                kCGImageSourceShouldCacheImmediately: true
            ]
            for (i, frameInfo) in frameInfoArray.enumerated() {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, opts as CFDictionary) else { continue }
                let delay = (frameInfo[kCGImagePropertyWebPDelayTime] as? TimeInterval)
                    ?? (frameInfo[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval)
                    ?? 0.1
                frames.append((cgImage, max(delay, 0.01)))
            }
        }

        guard !frames.isEmpty else { return }
        showFrame(0)
        guard frames.count > 1 else { return }
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func showFrame(_ index: Int) {
        frameIndex = index
        let cgImage = frames[index].image
        currentImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func scheduleNext() {
        let delay = frames[frameIndex].delay
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            let next = (self.frameIndex + 1) % self.frames.count
            self.showFrame(next)
            self.scheduleNext()
        }
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        // WebP
        if let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let d = webp[kCGImagePropertyWebPDelayTime] as? TimeInterval { return max(d, 0.01) }
            if let d = webp[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval { return max(d, 0.01) }
        }
        // GIF
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let d = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval { return max(d, 0.01) }
            if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval { return max(d, 0.01) }
        }
        // APNG
        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let d = png[kCGImagePropertyAPNGDelayTime] as? TimeInterval { return max(d, 0.01) }
            if let d = png[kCGImagePropertyAPNGUnclampedDelayTime] as? TimeInterval { return max(d, 0.01) }
        }
        return 0.1
    }
}

/// Frame-driven animated image view for formats NSImageView can't animate (e.g. WebP).
struct FrameAnimatedImageView: NSViewRepresentable {
    var animator: FrameAnimator

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = animator.currentImage
    }
}

/// Wraps NSImageView so animated GIF/APNG images play automatically.
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
    @State private var webpAnimator = FrameAnimator()

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
                                    if imageFile.url.pathExtension.lowercased() == "webp" {
                                        // NSImageView.animates only works for GIF; drive WebP frame-by-frame.
                                        FrameAnimatedImageView(animator: webpAnimator)
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
                        webpAnimator.stop()
                        guard !imageFile.isCloudOnly else { return }
                        if imageFile.isVideo {
                            player = AVPlayer(url: imageFile.url)
                        } else {
                            nsImage = await loadFullImage(url: imageFile.url)
                            // Start frame-driven animation for animated WebP after image loads
                            if imageFile.isAnimated,
                               imageFile.url.pathExtension.lowercased() == "webp" {
                                webpAnimator.load(url: imageFile.url)
                            }
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

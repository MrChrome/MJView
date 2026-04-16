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

/// Drives frame-by-frame animation for any animated image format using CGImageSource.
/// Also exposes scrubbing controls (seek, pause, play) and frame export.
@Observable
final class FrameAnimator {
    var currentImage: NSImage?
    var currentFrameIndex: Int = 0
    var frameCount: Int = 0
    var isPlaying: Bool = false

    private var frames: [(image: CGImage, delay: TimeInterval)] = []
    private var timer: Timer?

    func load(url: URL) {
        stop()
        frames = []
        currentFrameIndex = 0
        frameCount = 0
        currentImage = nil

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(source)

        // Build frame list, reading per-frame delay from WebP, GIF, or APNG metadata.
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let delay = Self.frameDelay(source: source, index: i)
            frames.append((cgImage, delay))
        }

        // Some animated WebP files report count=1 — fall back to the frame info array.
        if frames.count <= 1,
           let containerProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let webpDict = containerProps[kCGImagePropertyWebPDictionary] as? [CFString: Any],
           let frameInfoArray = webpDict[kCGImagePropertyWebPFrameInfoArray] as? [[CFString: Any]],
           frameInfoArray.count > 1 {
            frames = []
            let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            for (i, frameInfo) in frameInfoArray.enumerated() {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, opts as CFDictionary) else { continue }
                let delay = (frameInfo[kCGImagePropertyWebPDelayTime] as? TimeInterval)
                    ?? (frameInfo[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval)
                    ?? 0.1
                frames.append((cgImage, max(delay, 0.01)))
            }
        }

        guard !frames.isEmpty else { return }
        frameCount = frames.count
        showFrame(0)
        if frames.count > 1 {
            isPlaying = true
            scheduleNext()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }

    func play() {
        guard frames.count > 1, !isPlaying else { return }
        isPlaying = true
        scheduleNext()
    }

    /// Seek to a specific frame index and pause.
    func seek(to index: Int) {
        guard index >= 0, index < frames.count else { return }
        stop()
        showFrame(index)
    }

    /// Returns the CGImage for the current frame, for export.
    var currentCGImage: CGImage? {
        guard currentFrameIndex < frames.count else { return nil }
        return frames[currentFrameIndex].image
    }

    private func showFrame(_ index: Int) {
        currentFrameIndex = index
        let cgImage = frames[index].image
        currentImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func scheduleNext() {
        guard isPlaying else { return }
        let delay = frames[currentFrameIndex].delay
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            let next = (self.currentFrameIndex + 1) % self.frames.count
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

/// Scrubber bar and controls that overlay the animated image view.
struct FrameScrubbingView: View {
    var animator: FrameAnimator
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 10) {
                // Play / pause
                Button {
                    if animator.isPlaying { animator.stop() } else { animator.play() }
                } label: {
                    Image(systemName: animator.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(animator.isPlaying ? "Pause" : "Play")

                // Scrubber slider
                if animator.frameCount > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(animator.currentFrameIndex) },
                            set: { animator.seek(to: Int($0.rounded())) }
                        ),
                        in: 0...Double(max(animator.frameCount - 1, 1)),
                        step: 1
                    )
                }

                // Frame counter
                Text("\(animator.currentFrameIndex + 1) / \(animator.frameCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)

                // Export current frame
                Button {
                    onExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Export Current Frame as PNG")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }
}

/// Saves a CGImage as a PNG to a URL chosen by the user via NSSavePanel.
func exportFrameAsPNG(_ cgImage: CGImage, suggestedName: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = suggestedName
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, cgImage, nil)
    CGImageDestinationFinalize(dest)
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
    /// Incremented by ContentView whenever metadata (dimensions, animation) loads
    /// for the selected image. Forces this view to re-render even when ImageFile.==
    /// considers the file unchanged (it only compares URL + isCloudOnly).
    let metadataVersion: Int
    @Binding var isCropping: Bool
    @Binding var isScrubbing: Bool
    @Binding var isFlippedHorizontal: Bool
    @Binding var isFlippedVertical: Bool
    var onCropCompleted: ((URL, CropSaveMode) -> Void)?
    var onFlipCompleted: ((URL, CropSaveMode) -> Void)?
    var onShowPrompt: ((ImageFile) -> Void)?
    var onRenameImage: ((ImageFile) -> Void)?
    var onDeleteImage: ((ImageFile) -> Void)?

    @State private var nsImage: NSImage?
    @State private var player: AVPlayer?
    @State private var reloadCounter: Int = 0
    @State private var showCropSaveSheet: Bool = false
    @State private var pendingNormalizedRect: CGRect?
    @State private var cropError: String?
    @State private var showFlipSaveSheet: Bool = false
    @State private var flipError: String?
    /// Unified animator for all animated images — used for scrubbing and WebP playback.
    @State private var frameAnimator = FrameAnimator()

    // Zoom / pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomScaleTemp: CGFloat = 1.0   // live scale during active pinch
    @State private var panOffset: CGSize = .zero
    @State private var panOffsetTemp: CGSize = .zero  // live offset during active drag

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
                                    // All animated formats use FrameAnimatedImageView so the
                                    // scrubber can control playback uniformly.
                                    ZStack(alignment: .bottom) {
                                        FrameAnimatedImageView(animator: frameAnimator)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .aspectRatio(
                                                nsImage.size.width / max(nsImage.size.height, 1),
                                                contentMode: .fit
                                            )
                                            .scaleEffect(
                                                x: isFlippedHorizontal ? -1 : 1,
                                                y: isFlippedVertical ? -1 : 1
                                            )
                                            .padding(8)
                                            .scaleEffect(effectiveZoomScale)
                                            .offset(effectivePanOffset)
                                            .gesture(zoomPanGesture)
                                            .onTapGesture(count: 2) {
                                                withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                                            }
                                            .fileDrag(when: zoomScale <= 1.0, url: imageFile.url)
                                            .onHover { hovering in
                                                if hovering && effectiveZoomScale > 1.0 {
                                                    NSCursor.openHand.push()
                                                } else {
                                                    NSCursor.pop()
                                                }
                                            }

                                        if isScrubbing {
                                            FrameScrubbingView(animator: frameAnimator) {
                                                if let cgImage = frameAnimator.currentCGImage {
                                                    let base = imageFile.url.deletingPathExtension().lastPathComponent
                                                    exportFrameAsPNG(cgImage, suggestedName: "\(base)_frame\(frameAnimator.currentFrameIndex + 1).png")
                                                }
                                            }
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
                                                .scaleEffect(
                                                    x: isFlippedHorizontal ? -1 : 1,
                                                    y: isFlippedVertical ? -1 : 1
                                                )
                                                .padding(8)
                                                .scaleEffect(effectiveZoomScale)
                                                .offset(effectivePanOffset)
                                                .fileDrag(when: zoomScale <= 1.0, url: imageFile.url)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                        .gesture(zoomPanGesture)
                                        .onTapGesture(count: 2) {
                                            guard !isCropping else { return }
                                            withAnimation(.easeOut(duration: 0.2)) { resetZoom() }
                                        }
                                        .onHover { hovering in
                                            if hovering && effectiveZoomScale > 1.0 {
                                                NSCursor.openHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }

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
                    .contextMenu {
                        if imageFile.url.pathExtension.lowercased() == "png" {
                            Button("Show Prompt") {
                                onShowPrompt?(imageFile)
                            }
                            Divider()
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([imageFile.url])
                        }
                        Button("Rename…") {
                            onRenameImage?(imageFile)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            onDeleteImage?(imageFile)
                        }
                    }
                    .task(id: "\(imageFile.url.path)|\(imageFile.isCloudOnly)|\(reloadCounter)") {
                        nsImage = nil
                        player?.pause()
                        player = nil
                        frameAnimator.stop()
                        guard !imageFile.isCloudOnly else { return }
                        if imageFile.isVideo {
                            player = AVPlayer(url: imageFile.url)
                        } else {
                            nsImage = await loadFullImage(url: imageFile.url)
                            // Load frame animator for all animated images (WebP, GIF, APNG)
                            if imageFile.isAnimated {
                                frameAnimator.load(url: imageFile.url)
                            }
                        }
                    }
                    .onChange(of: imageFile) {
                        // Exit crop and scrubber modes when the selected image changes
                        isCropping = false
                        if !imageFile.isAnimated {
                            isScrubbing = false
                        }
                        // Reset flip state for the new image
                        isFlippedHorizontal = false
                        isFlippedVertical = false
                        // Reset zoom for the new image
                        resetZoom()
                    }
                    .onChange(of: isCropping) {
                        if isCropping { resetZoom() }
                    }
                    .onChange(of: isScrubbing) {
                        if isScrubbing {
                            frameAnimator.stop()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        // Show a save button whenever a flip is active (non-video, non-cloud images only)
                        if (isFlippedHorizontal || isFlippedVertical) && !imageFile.isVideo && !imageFile.isCloudOnly {
                            Button {
                                showFlipSaveSheet = true
                            } label: {
                                Label("Save Flipped Image", systemImage: "square.and.arrow.down")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                        }
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
                    .sheet(isPresented: $showFlipSaveSheet) {
                        CropSaveSheet(
                            originalFileName: imageFile.name,
                            newFileName: CropService.uniqueFlippedURL(for: imageFile.url).lastPathComponent,
                            onSave: { mode in
                                performFlip(imageFile: imageFile, mode: mode)
                                showFlipSaveSheet = false
                            },
                            onCancel: {
                                showFlipSaveSheet = false
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
                    .alert("Flip Error", isPresented: Binding(
                        get: { flipError != nil },
                        set: { if !$0 { flipError = nil } }
                    )) {
                        Button("OK") { flipError = nil }
                    } message: {
                        Text(flipError ?? "")
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
                    if !imageFile.isVideo {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.secondary)
                            Slider(value: $zoomScale, in: 1.0...5.0)
                                .controlSize(.mini)
                                .frame(width: 80)
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                    }
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
        .onChange(of: zoomScale) {
            if zoomScale <= 1.0 {
                panOffset = .zero
                panOffsetTemp = .zero
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

    private func performFlip(imageFile: ImageFile, mode: CropSaveMode) {
        do {
            let savedURL = try CropService.flipAndSave(
                sourceURL: imageFile.url,
                flipHorizontal: isFlippedHorizontal,
                flipVertical: isFlippedVertical,
                saveMode: mode
            )
            // Reset visual flip state — the saved file is now the canonical version
            isFlippedHorizontal = false
            isFlippedVertical = false
            if mode == .overwrite {
                reloadCounter += 1
            }
            onFlipCompleted?(savedURL, mode)
        } catch {
            flipError = error.localizedDescription
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

    // MARK: - Zoom / Pan helpers

    private var effectiveZoomScale: CGFloat {
        max(1.0, min(5.0, zoomScale * zoomScaleTemp))
    }

    private var effectivePanOffset: CGSize {
        CGSize(
            width: panOffset.width + panOffsetTemp.width,
            height: panOffset.height + panOffsetTemp.height
        )
    }

    private var zoomPanGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScaleTemp = value
            }
            .onEnded { value in
                zoomScale = max(1.0, min(5.0, zoomScale * value))
                zoomScaleTemp = 1.0
                if zoomScale <= 1.0 {
                    zoomScale = 1.0
                    panOffset = .zero
                }
            }
            .simultaneously(with:
                DragGesture()
                    .onChanged { value in
                        guard effectiveZoomScale > 1.0 else { return }
                        panOffsetTemp = value.translation
                    }
                    .onEnded { value in
                        guard effectiveZoomScale > 1.0 else { return }
                        panOffset = CGSize(
                            width: panOffset.width + value.translation.width,
                            height: panOffset.height + value.translation.height
                        )
                        panOffsetTemp = .zero
                    }
            )
    }

    private func resetZoom() {
        zoomScale = 1.0
        zoomScaleTemp = 1.0
        panOffset = .zero
        panOffsetTemp = .zero
    }
}

private extension View {
    /// Applies `.onDrag` for file drag-and-drop only when `enabled` is true.
    /// When zoomed in, this is disabled so the pan DragGesture can fire instead.
    @ViewBuilder
    func fileDrag(when enabled: Bool, url: URL) -> some View {
        if enabled {
            self.onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
        } else {
            self
        }
    }
}

//
//  CropOverlayView.swift
//  MJView
//

import SwiftUI

private enum CropHandle: Hashable {
    case topLeft, top, topRight
    case left, body, right
    case bottomLeft, bottom, bottomRight
}

/// Crop overlay that sits on top of the image inside a GeometryReader.
///
/// Coordinate convention: all rects/points are in the GeometryReader's local
/// coordinate space (origin = top-left of the GeometryReader frame).
/// `imageOriginInView` and `imageSizeInView` describe where the image is
/// rendered within that space (accounting for padding and aspect-fit).
struct CropOverlayView: View {
    let imageSizeInView: CGSize
    let imageOriginInView: CGPoint
    let onCancel: () -> Void
    let onApply: (CGRect) -> Void   // normalized rect 0...1

    @State private var cropRect: CGRect
    @State private var activeHandle: CropHandle?
    @State private var rectAtDragStart: CGRect = .zero
    @State private var hoverHandle: CropHandle = .body

    private let handleSize: CGFloat = 12
    private let hitRadius: CGFloat = 20
    private let minimumCropSize: CGFloat = 20

    init(
        imageSizeInView: CGSize,
        imageOriginInView: CGPoint,
        onCancel: @escaping () -> Void,
        onApply: @escaping (CGRect) -> Void
    ) {
        self.imageSizeInView   = imageSizeInView
        self.imageOriginInView = imageOriginInView
        self.onCancel          = onCancel
        self.onApply           = onApply
        _cropRect = State(initialValue: CGRect(origin: imageOriginInView,
                                               size: imageSizeInView))
    }

    var body: some View {
        // Fill the full GeometryReader frame so .local drag coordinates match
        // the coordinate space used by imageOriginInView / cropRect.
        ZStack(alignment: .top) {
            // 1. Dimmed mask (even-odd: image rect minus crop rect)
            Path { path in
                path.addRect(CGRect(origin: imageOriginInView, size: imageSizeInView))
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // 2. Crop border
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)

            // 3. Rule-of-thirds grid
            Canvas { context, _ in
                var path = Path()
                for line in thirdLines() {
                    path.move(to: line.0)
                    path.addLine(to: line.1)
                }
                context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
            }
            .allowsHitTesting(false)

            // 4. Single drag gesture covering the full overlay.
            //    Uses .local so coordinates are in the ZStack's own frame,
            //    which matches the imageOriginInView / cropRect coordinate system.
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let location) = phase {
                        hoverHandle = handle(for: location)
                    }
                }
                .pointerStyle(resizePointerStyle(for: hoverHandle))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            if activeHandle == nil {
                                activeHandle = handle(for: value.startLocation)
                                rectAtDragStart = cropRect
                            }
                            guard let h = activeHandle else { return }
                            cropRect = updatedRect(handle: h,
                                                   translation: value.translation,
                                                   from: rectAtDragStart)
                        }
                        .onEnded { _ in activeHandle = nil }
                )

            // 5. Visual handles (no gestures; drag is handled above)
            ForEach(allHandles, id: \.self) { h in
                handleView(for: h)
            }

            // 6. Apply / Cancel bar at the bottom of the overlay
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                    Button("Apply") { onApply(normalizedRect()) }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 12)
            }
        }
        // Must fill the entire parent (GeometryReader) so .local coordinates match.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Handles

    private var allHandles: [CropHandle] {
        [.topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight]
    }

    @ViewBuilder
    private func handleView(for handle: CropHandle) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: handleSize, height: handleSize)
            // Expand the tappable area without changing visual size
            .padding(hitRadius - handleSize / 2)
            .contentShape(Rectangle())
            .position(handlePosition(for: handle))
            .pointerStyle(resizePointerStyle(for: handle))
            .allowsHitTesting(false) // gesture is handled by the full-overlay layer
    }

    private func handlePosition(for handle: CropHandle) -> CGPoint {
        let r = cropRect
        switch handle {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .top:         return CGPoint(x: r.midX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .left:        return CGPoint(x: r.minX, y: r.midY)
        case .right:       return CGPoint(x: r.maxX, y: r.midY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .bottom:      return CGPoint(x: r.midX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .body:        return CGPoint(x: r.midX, y: r.midY)
        }
    }

    private func resizePointerStyle(for handle: CropHandle) -> PointerStyle {
        switch handle {
        case .topLeft:     return .frameResize(position: .topLeading)
        case .top:         return .frameResize(position: .top)
        case .topRight:    return .frameResize(position: .topTrailing)
        case .left:        return .frameResize(position: .leading)
        case .right:       return .frameResize(position: .trailing)
        case .bottomLeft:  return .frameResize(position: .bottomLeading)
        case .bottom:      return .frameResize(position: .bottom)
        case .bottomRight: return .frameResize(position: .bottomTrailing)
        case .body:        return .grabIdle
        }
    }

    // MARK: - Hit-testing

    private func handle(for point: CGPoint) -> CropHandle {
        for h in allHandles {
            let pos = handlePosition(for: h)
            let dist = hypot(point.x - pos.x, point.y - pos.y)
            if dist <= hitRadius { return h }
        }
        return cropRect.contains(point) ? .body : .body
    }

    // MARK: - Rect mutation

    private func updatedRect(handle: CropHandle, translation: CGSize, from base: CGRect) -> CGRect {
        let dx = translation.width
        let dy = translation.height
        let bounds = CGRect(origin: imageOriginInView, size: imageSizeInView)

        var minX = base.minX, minY = base.minY
        var maxX = base.maxX, maxY = base.maxY

        switch handle {
        case .topLeft:
            minX = min(maxX - minimumCropSize, base.minX + dx)
            minY = min(maxY - minimumCropSize, base.minY + dy)
        case .top:
            minY = min(maxY - minimumCropSize, base.minY + dy)
        case .topRight:
            maxX = max(minX + minimumCropSize, base.maxX + dx)
            minY = min(maxY - minimumCropSize, base.minY + dy)
        case .left:
            minX = min(maxX - minimumCropSize, base.minX + dx)
        case .right:
            maxX = max(minX + minimumCropSize, base.maxX + dx)
        case .bottomLeft:
            minX = min(maxX - minimumCropSize, base.minX + dx)
            maxY = max(minY + minimumCropSize, base.maxY + dy)
        case .bottom:
            maxY = max(minY + minimumCropSize, base.maxY + dy)
        case .bottomRight:
            maxX = max(minX + minimumCropSize, base.maxX + dx)
            maxY = max(minY + minimumCropSize, base.maxY + dy)
        case .body:
            let w = base.width, h = base.height
            minX = base.minX + dx; minY = base.minY + dy
            maxX = minX + w;       maxY = minY + h
            if minX < bounds.minX { minX = bounds.minX; maxX = minX + w }
            if maxX > bounds.maxX { maxX = bounds.maxX; minX = maxX - w }
            if minY < bounds.minY { minY = bounds.minY; maxY = minY + h }
            if maxY > bounds.maxY { maxY = bounds.maxY; minY = maxY - h }
        }

        if handle != .body {
            minX = max(bounds.minX, minX); minY = max(bounds.minY, minY)
            maxX = min(bounds.maxX, maxX); maxY = min(bounds.maxY, maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Helpers

    private func thirdLines() -> [(CGPoint, CGPoint)] {
        let r = cropRect
        let w3 = r.width / 3, h3 = r.height / 3
        return [
            (CGPoint(x: r.minX + w3,     y: r.minY), CGPoint(x: r.minX + w3,     y: r.maxY)),
            (CGPoint(x: r.minX + 2*w3,   y: r.minY), CGPoint(x: r.minX + 2*w3,   y: r.maxY)),
            (CGPoint(x: r.minX, y: r.minY + h3),     CGPoint(x: r.maxX, y: r.minY + h3)),
            (CGPoint(x: r.minX, y: r.minY + 2*h3),   CGPoint(x: r.maxX, y: r.minY + 2*h3))
        ]
    }

    private func normalizedRect() -> CGRect {
        CGRect(
            x: (cropRect.minX - imageOriginInView.x) / imageSizeInView.width,
            y: (cropRect.minY - imageOriginInView.y) / imageSizeInView.height,
            width:  cropRect.width  / imageSizeInView.width,
            height: cropRect.height / imageSizeInView.height
        )
    }
}

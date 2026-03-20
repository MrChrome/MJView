//
//  ThumbnailView.swift
//  MJView
//

import SwiftUI
import AppKit

struct ThumbnailView: View {
    let imageFile: ImageFile
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        AsyncThumbnailImage(url: imageFile.url, size: size)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
    }
}

struct AsyncThumbnailImage: View {
    let url: URL
    let size: CGFloat

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .task(id: url) {
            nsImage = await Self.loadThumbnail(url: url, size: size)
        }
    }

    private static func loadThumbnail(url: URL, size: CGFloat) async -> NSImage? {
        let pixelSize = size * 2 // Retina
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

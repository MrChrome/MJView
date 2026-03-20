//
//  ThumbnailView.swift
//  MJView
//

import SwiftUI
import AppKit
import AVFoundation

struct ThumbnailView: View {
    let imageFile: ImageFile
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        AsyncThumbnailImage(url: imageFile.url, isVideo: imageFile.isVideo, size: size)
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
    let isVideo: Bool
    let size: CGFloat

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(alignment: .bottomLeading) {
                        if isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: size * 0.22))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .padding(4)
                        }
                    }
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
            if isVideo {
                nsImage = await Self.loadVideoThumbnail(url: url)
            } else {
                nsImage = await Self.loadImageThumbnail(url: url, size: size)
            }
        }
    }

    private static func loadImageThumbnail(url: URL, size: CGFloat) async -> NSImage? {
        await Task.detached {
            let pixelSize = size * 2
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
        }.value
    }

    private static func loadVideoThumbnail(url: URL) async -> NSImage? {
        await Task.detached {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)
            let time = CMTime(seconds: 0, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}

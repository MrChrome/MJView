//
//  ThumbnailView.swift
//  MJView
//

import SwiftUI
import AppKit
import AVFoundation
import QuickLookThumbnailing

// Shared in-memory thumbnail cache. NSCache handles memory pressure automatically.
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    func image(for url: URL, size: CGFloat, modifiedDate: Date) -> NSImage? {
        cache.object(forKey: cacheKey(url, size, modifiedDate) as NSString)
    }

    func store(_ image: NSImage, for url: URL, size: CGFloat, modifiedDate: Date) {
        cache.setObject(image, forKey: cacheKey(url, size, modifiedDate) as NSString)
    }

    private func cacheKey(_ url: URL, _ size: CGFloat, _ date: Date) -> String {
        "\(url.path)|\(Int(size))|\(date.timeIntervalSinceReferenceDate)"
    }
}

struct ThumbnailView: View {
    let imageFile: ImageFile
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        AsyncThumbnailImage(url: imageFile.url, isVideo: imageFile.isVideo, isCloudOnly: imageFile.isCloudOnly, size: size, modifiedDate: imageFile.modifiedDate)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                if imageFile.isVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if imageFile.isCloudOnly {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
    }
}

struct AsyncThumbnailImage: View {
    let url: URL
    let isVideo: Bool
    let isCloudOnly: Bool
    let size: CGFloat
    let modifiedDate: Date

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isCloudOnly {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
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
        .task(id: "\(url.path)|\(isCloudOnly)") {
            // 1. In-memory cache — synchronous, no async overhead
            if let cached = ThumbnailCache.shared.image(for: url, size: size, modifiedDate: modifiedDate) {
                nsImage = cached
                return
            }
            // 2. Disk cache — fast local SQLite read, skips network entirely
            if let cached = await ThumbnailDatabase.shared.image(for: url, size: size, modifiedDate: modifiedDate) {
                ThumbnailCache.shared.store(cached, for: url, size: size, modifiedDate: modifiedDate)
                nsImage = cached
                return
            }
            // 3. Decode from file / network
            let loaded: NSImage?
            if isCloudOnly {
                loaded = await Self.loadQLThumbnail(url: url, size: size)
            } else if isVideo {
                loaded = await Self.loadVideoThumbnail(url: url)
            } else {
                loaded = await Self.loadImageThumbnail(url: url, size: size)
            }
            if let loaded {
                ThumbnailCache.shared.store(loaded, for: url, size: size, modifiedDate: modifiedDate)
                await ThumbnailDatabase.shared.store(loaded, for: url, size: size, modifiedDate: modifiedDate, isCloudOnly: isCloudOnly)
            }
            nsImage = loaded
        }
    }

    private static func loadQLThumbnail(url: URL, size: CGFloat) async -> NSImage? {
        let pixelSize = size * 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixelSize, height: pixelSize),
            scale: 1.0,
            representationTypes: .all
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
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
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

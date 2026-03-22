//
//  CropService.swift
//  MJView
//

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum CropSaveMode {
    case overwrite
    case saveAsNew
}

enum CropError: LocalizedError {
    case cannotLoadImage
    case cropFailed
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage:         return "Could not load the image file."
        case .cropFailed:              return "The crop operation failed."
        case .cannotCreateDestination: return "Could not create the output file."
        case .writeFailed:             return "Failed to write the cropped image."
        }
    }
}

struct CropService {

    /// Crops `sourceURL` to `normalizedRect` (each component in 0...1) and writes to disk.
    /// Returns the URL of the saved file.
    static func cropAndSave(
        sourceURL: URL,
        normalizedRect: CGRect,
        saveMode: CropSaveMode
    ) throws -> URL {
        // Load the full-resolution CGImage
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CropError.cannotLoadImage
        }

        // Convert normalized rect to pixel coordinates
        let pixelWidth  = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let cropPixelRect = CGRect(
            x: (normalizedRect.origin.x * pixelWidth).rounded(),
            y: (normalizedRect.origin.y * pixelHeight).rounded(),
            width: (normalizedRect.size.width * pixelWidth).rounded(),
            height: (normalizedRect.size.height * pixelHeight).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        guard let croppedCGImage = cgImage.cropping(to: cropPixelRect) else {
            throw CropError.cropFailed
        }

        // Determine destination URL
        let destinationURL: URL
        switch saveMode {
        case .overwrite:  destinationURL = sourceURL
        case .saveAsNew:  destinationURL = uniqueURL(for: sourceURL)
        }

        // Write using CGImageDestination, preserving format and metadata
        let uti = outputUTType(for: sourceURL)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            uti.identifier as CFString,
            1, nil
        ) else {
            throw CropError.cannotCreateDestination
        }

        // Copy metadata from original (EXIF, color profile, etc.)
        let originalProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
        CGImageDestinationAddImage(destination, croppedCGImage, originalProperties)

        guard CGImageDestinationFinalize(destination) else {
            throw CropError.writeFailed
        }

        return destinationURL
    }

    /// Generates `<stem>_cropped.<ext>`, incrementing a counter if the name already exists.
    static func uniqueURL(for sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let stem      = sourceURL.deletingPathExtension().lastPathComponent
        let ext       = sourceURL.pathExtension

        let baseName  = "\(stem)_cropped"
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter   = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    /// Maps file extension to a UTType for CGImageDestination output.
    static func outputUTType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png":         return .png
        case "tiff", "tif": return .tiff
        case "heic":        return .heic
        case "bmp":         return .bmp
        case "gif":         return .gif
        case "webp":        return .webP
        default:            return .png
        }
    }
}

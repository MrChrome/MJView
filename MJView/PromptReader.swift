//
//  PromptReader.swift
//  MJView
//
//  Reads the MidJourney prompt embedded in a PNG's XMP metadata.
//  Logic ported from Program.cs.
//

import Foundation
import Compression

enum PromptReader {

    /// Extracts the MidJourney prompt from a PNG file's XMP UserComment, or returns nil.
    static func readPrompt(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "png" else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Validate PNG signature
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count > 8,
              data.prefix(8).elementsEqual(pngSignature) else { return nil }

        var offset = 8
        while offset + 8 <= data.count {
            // Read chunk length (4 bytes big-endian) and type (4 bytes ASCII)
            let length = Int(readUInt32BE(data, at: offset))
            let typeBytes = data[offset + 4 ..< offset + 8]
            guard let chunkType = String(bytes: typeBytes, encoding: .ascii) else { break }
            offset += 8

            guard offset + length <= data.count else { break }
            let chunkData = data[offset ..< offset + length]
            offset += length + 4 // skip data + CRC

            if chunkType == "iTXt" {
                if let comment = extractUserCommentFromXmp(Array(chunkData)) {
                    return extractPromptFromJSON(comment)
                }
            } else if chunkType == "IEND" {
                break
            }
        }
        return nil
    }

    // MARK: - PNG iTXt parsing

    private static func extractUserCommentFromXmp(_ bytes: [UInt8]) -> String? {
        // iTXt layout: keyword\0 compressionFlag(1) compressionMethod(1) language\0 translatedKeyword\0 text
        guard let keywordEnd = bytes.firstIndex(of: 0) else { return nil }
        let keyword = String(bytes: bytes[0..<keywordEnd], encoding: .isoLatin1) ?? ""
        guard keyword.caseInsensitiveCompare("XML:com.adobe.xmp") == .orderedSame else { return nil }

        guard keywordEnd + 3 <= bytes.count else { return nil }
        let compressionFlag = bytes[keywordEnd + 1]
        var pos = keywordEnd + 3

        // Skip language tag
        guard let langEnd = bytes[pos...].firstIndex(of: 0) else { return nil }
        pos = langEnd + 1

        // Skip translated keyword
        guard let transEnd = bytes[pos...].firstIndex(of: 0) else { return nil }
        pos = transEnd + 1

        guard pos <= bytes.count else { return nil }
        let textBytes: [UInt8]

        if compressionFlag != 0 {
            // Deflate-compressed: skip 2-byte zlib header then inflate
            guard pos + 2 <= bytes.count else { return nil }
            let compressed = bytes[(pos + 2)...]
            guard let decompressed = inflate(Array(compressed)) else { return nil }
            textBytes = decompressed
        } else {
            textBytes = Array(bytes[pos...])
        }

        guard let xmp = String(bytes: textBytes, encoding: .utf8) else { return nil }
        return extractUserCommentFromXML(xmp)
    }

    // MARK: - XMP / JSON parsing

    private static func extractUserCommentFromXML(_ xmp: String) -> String? {
        // Find exif:UserComment > rdf:Alt > rdf:li text content via XMLParser
        let parser = XMPUserCommentParser(xmp: xmp)
        return parser.parse()
    }

    private static func extractPromptFromJSON(_ comment: String) -> String? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Case-insensitive search for property "c"
        for (key, value) in json {
            if key.caseInsensitiveCompare("c") == .orderedSame {
                if let str = value as? String, !str.isEmpty { return str }
                return nil
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b = data[offset ..< offset + 4]
        return (UInt32(b[b.startIndex]) << 24)
             | (UInt32(b[b.startIndex + 1]) << 16)
             | (UInt32(b[b.startIndex + 2]) << 8)
             |  UInt32(b[b.startIndex + 3])
    }

    private static func inflate(_ bytes: [UInt8]) -> [UInt8]? {
        // Raw deflate decompression (zlib header already stripped by caller)
        let srcSize = bytes.count
        guard srcSize > 0 else { return nil }
        // Allocate an output buffer; grow if needed
        var dstSize = max(srcSize * 4, 65536)
        var dst = [UInt8](repeating: 0, count: dstSize)
        var written = 0
        bytes.withUnsafeBytes { src in
            guard let srcPtr = src.baseAddress else { return }
            written = compression_decode_buffer(&dst, dstSize, srcPtr, srcSize, nil, COMPRESSION_ZLIB)
        }
        // If output was truncated, retry with a larger buffer
        if written == dstSize {
            dstSize *= 4
            dst = [UInt8](repeating: 0, count: dstSize)
            bytes.withUnsafeBytes { src in
                guard let srcPtr = src.baseAddress else { return }
                written = compression_decode_buffer(&dst, dstSize, srcPtr, srcSize, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Array(dst.prefix(written))
    }
}

// MARK: - XMP parser

/// Minimal SAX parser that extracts the text of exif:UserComment/rdf:Alt/rdf:li
private final class XMPUserCommentParser: NSObject, XMLParserDelegate {
    private let xmp: String
    private var inUserComment = false
    private var inAlt = false
    private var inLi = false
    private var result: String?
    private var currentText = ""

    init(xmp: String) {
        self.xmp = xmp
    }

    func parse() -> String? {
        guard let data = xmp.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "UserComment" && (namespaceURI?.contains("exif") == true || elementName.contains("exif")) {
            inUserComment = true
        } else if local == "Alt" && inUserComment {
            inAlt = true
        } else if local == "li" && inAlt {
            inLi = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inLi { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "li" && inLi {
            if result == nil { result = currentText }
            inLi = false
        } else if local == "Alt" { inAlt = false }
        else if local == "UserComment" { inUserComment = false }
    }
}

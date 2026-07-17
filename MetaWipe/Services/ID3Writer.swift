import Foundation

/// Writes back a small set of common ID3v2.3/ID3v2.4 text frames (title, artist, album, a plain
/// comment, etc. — see `ID3TextFrameNames`) directly, bypassing exiftool.
///
/// exiftool can read ID3 tags from MP3 files but has never supported writing them (confirmed via
/// its own "-listwf" list of writable extensions, which excludes MP3) — see the notes on
/// `ExifToolBridge.readTags`. This is a small, deliberately narrow writer covering only simple
/// single-string text frames plus Comment, not a general ID3v2 library: it refuses to touch
/// anything it isn't confident it parsed correctly (compressed/encrypted/unsynchronised frames,
/// extended headers, ID3v2.2) rather than risk corrupting the file.
enum ID3Writer {
    enum WriterError: LocalizedError {
        case notAnID3v2File
        case unsupportedVersion(UInt8)
        case unsynchronisationNotSupported
        case extendedHeaderNotSupported
        case invalidFrameID(String)
        case frameOverrunsTag(String)
        case compressedFrameNotSupported(String)
        case encryptedFrameNotSupported(String)
        case unsynchronisedFrameNotSupported(String)
        case dataLengthIndicatorNotSupported(String)
        case unknownTextEncoding(UInt8)
        case invalidFrameData(String)
        case cannotEncodeText
        case frameNotFound(String)
        case ambiguousFrame(String)

        var errorDescription: String? {
            switch self {
            case .notAnID3v2File:
                return "This file doesn't have an ID3v2 tag to write to."
            case .unsupportedVersion(let version):
                return "ID3v2.\(version) tags aren't supported for writing (only v2.3 and v2.4 are)."
            case .unsynchronisationNotSupported:
                return "This file's ID3 tag uses whole-tag unsynchronisation, which isn't supported for writing."
            case .extendedHeaderNotSupported:
                return "This file's ID3 tag has an extended header, which isn't supported for writing."
            case .invalidFrameID(let id):
                return "Encountered an invalid ID3 frame ID (\(id)); refusing to write to avoid corrupting the file."
            case .frameOverrunsTag(let id):
                return "The \(id) frame's declared size doesn't fit within the tag; refusing to write to avoid corrupting the file."
            case .compressedFrameNotSupported(let id):
                return "The \(id) frame is compressed, which isn't supported for writing."
            case .encryptedFrameNotSupported(let id):
                return "The \(id) frame is encrypted, which isn't supported for writing."
            case .unsynchronisedFrameNotSupported(let id):
                return "The \(id) frame uses per-frame unsynchronisation, which isn't supported for writing."
            case .dataLengthIndicatorNotSupported(let id):
                return "The \(id) frame has a data length indicator, which isn't supported for writing."
            case .unknownTextEncoding(let encoding):
                return "Unknown text encoding (\(encoding)) in an ID3 frame."
            case .invalidFrameData(let id):
                return "The \(id) frame's data couldn't be parsed."
            case .cannotEncodeText:
                return "Couldn't encode the new tag value as text."
            case .frameNotFound(let id):
                return "Couldn't find the \(id) frame to update."
            case .ambiguousFrame(let id):
                return "Found more than one \(id) frame and couldn't determine which one to update."
            }
        }
    }

    private struct Frame {
        let id: String
        let flags: UInt16
        var data: Data
    }

    private struct Tag {
        let versionMajor: UInt8
        let headerFlags: UInt8
        var frames: [Frame]
        let declaredBodySize: Int
        let audioOffset: Int
    }

    /// Rewrites only the tags the caller marks as edited. Reads the whole file into memory,
    /// patches the relevant ID3v2 frames, and writes the result back with a plain (non-atomic)
    /// `Data.write(to:)` — that overwrites the existing inode directly rather than writing a
    /// temp file and renaming over the original, so extended attributes (Finder comments/tags,
    /// quarantine flag) survive, mirroring exiftool's "-overwrite_original_in_place" in
    /// `ExifToolBridge.writeTags`.
    static func write(url: URL, tags: [MetadataTag]) throws {
        let editable = tags.filter { $0.isEditable }
        guard !editable.isEmpty else { return }

        let originalData = try Data(contentsOf: url)
        var tag = try parse(originalData)

        for metaTag in editable {
            guard metaTag.group == "ID3v2_3" || metaTag.group == "ID3v2_4" else { continue }

            if let frameID = ID3TextFrameNames.frameIDsByTagName[metaTag.name] {
                let matchIndices = tag.frames.indices.filter { tag.frames[$0].id == frameID }
                let index: Int
                if matchIndices.count == 1 {
                    index = matchIndices[0]
                } else if matchIndices.isEmpty {
                    throw WriterError.frameNotFound(frameID)
                } else if frameID == "COMM" {
                    index = try resolveCommentFrame(matchIndices: matchIndices, frames: tag.frames, tagName: metaTag.name)
                } else {
                    throw WriterError.ambiguousFrame(frameID)
                }

                let newFrameData: Data
                if frameID == "COMM" {
                    newFrameData = try rewriteCommentFrame(tag.frames[index], newText: metaTag.value)
                } else {
                    newFrameData = try rewriteTextFrame(tag.frames[index], newValue: metaTag.value)
                }
                tag.frames[index].data = newFrameData
            } else {
                let (frameID, index) = try resolveUserDefinedFrame(tagName: metaTag.name, frames: tag.frames)
                let newFrameData = frameID == "WXXX"
                    ? try rewriteUserURLFrame(tag.frames[index], newValue: metaTag.value)
                    : try rewriteDescribedTextFrame(tag.frames[index], prefixLength: 0, newValue: metaTag.value)
                tag.frames[index].data = newFrameData
            }
        }

        let newTagBytes = try rebuildTag(tag)
        let audioBytes = originalData.subdata(in: tag.audioOffset..<originalData.count)
        try (newTagBytes + audioBytes).write(to: url)
    }

    /// The exiftool-style tag names (e.g. "SourceUrl") of TXXX/WXXX frames in `data` whose
    /// description resolves unambiguously to exactly one frame — i.e. the ones safe to offer
    /// for editing. Called from `ExifToolBridge.readTags` to flag `MetadataTag.isUserDefinedID3FrameEditable`;
    /// `write` re-derives the same match independently rather than trusting this set, so this
    /// is purely advisory for the UI.
    static func editableUserDefinedFrameNames(data: Data) -> Set<String> {
        guard let tag = try? parse(data) else { return [] }
        var counts: [String: Int] = [:]
        for frame in tag.frames {
            guard frame.id == "TXXX" || frame.id == "WXXX" else { continue }
            guard let name = try? userDefinedFrameName(frame) else { continue }
            counts[name, default: 0] += 1
        }
        return Set(counts.filter { $0.value == 1 }.keys)
    }

    // MARK: - Parsing

    private static func parse(_ data: Data) throws -> Tag {
        guard data.count >= 10, data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { // "ID3"
            throw WriterError.notAnID3v2File
        }
        let major = data[3]
        let headerFlags = data[5]
        guard major == 3 || major == 4 else { throw WriterError.unsupportedVersion(major) }

        let unsynchronised = headerFlags & 0x80 != 0
        let hasExtendedHeader = headerFlags & 0x40 != 0
        let hasFooter = major == 4 && (headerFlags & 0x10 != 0)
        guard !unsynchronised else { throw WriterError.unsynchronisationNotSupported }
        guard !hasExtendedHeader else { throw WriterError.extendedHeaderNotSupported }

        let declaredBodySize = syncsafeDecode(data, at: 6)
        let tagEnd = 10 + declaredBodySize
        guard tagEnd <= data.count else { throw WriterError.frameOverrunsTag("(tag header)") }

        var frames: [Frame] = []
        var pos = 10
        while pos < tagEnd {
            guard tagEnd - pos >= 10 else { break }
            let idData = data.subdata(in: pos..<(pos + 4))
            if idData == Data([0, 0, 0, 0]) { break } // padding begins

            guard
                let frameID = String(data: idData, encoding: .ascii),
                frameID.allSatisfy({ ($0.isASCII && $0.isNumber) || ($0.isASCII && $0.isUppercase) })
            else {
                throw WriterError.invalidFrameID(idData.map { String(format: "%02x", $0) }.joined())
            }

            let frameSize = major == 4 ? syncsafeDecode(data, at: pos + 4) : plainBEDecode(data, at: pos + 4)
            let flags = (UInt16(data[pos + 8]) << 8) | UInt16(data[pos + 9])

            if major == 4 {
                guard flags & 0x0008 == 0 else { throw WriterError.compressedFrameNotSupported(frameID) }
                guard flags & 0x0004 == 0 else { throw WriterError.encryptedFrameNotSupported(frameID) }
                guard flags & 0x0002 == 0 else { throw WriterError.unsynchronisedFrameNotSupported(frameID) }
                guard flags & 0x0001 == 0 else { throw WriterError.dataLengthIndicatorNotSupported(frameID) }
            } else {
                guard flags & 0x0080 == 0 else { throw WriterError.compressedFrameNotSupported(frameID) }
                guard flags & 0x0040 == 0 else { throw WriterError.encryptedFrameNotSupported(frameID) }
            }

            let frameDataStart = pos + 10
            let frameDataEnd = frameDataStart + frameSize
            guard frameDataEnd <= tagEnd else { throw WriterError.frameOverrunsTag(frameID) }
            frames.append(Frame(id: frameID, flags: flags, data: data.subdata(in: frameDataStart..<frameDataEnd)))
            pos = frameDataEnd
        }

        var audioOffset = tagEnd
        if hasFooter { audioOffset += 10 }
        return Tag(versionMajor: major, headerFlags: headerFlags, frames: frames, declaredBodySize: declaredBodySize, audioOffset: audioOffset)
    }

    private static func resolveCommentFrame(matchIndices: [Int], frames: [Frame], tagName: String) throws -> Int {
        let prefix = "Comment-"
        guard tagName.hasPrefix(prefix) else { throw WriterError.ambiguousFrame("COMM") }
        let langCode = tagName.dropFirst(prefix.count).lowercased()
        let candidates = matchIndices.filter { index in
            let raw = frames[index].data
            guard raw.count >= 4 else { return false }
            let lang = raw.subdata(in: 1..<4)
            return String(data: lang, encoding: .ascii)?.lowercased() == langCode
        }
        guard candidates.count == 1 else { throw WriterError.ambiguousFrame("COMM") }
        return candidates[0]
    }

    /// Finds the single TXXX (`UserDefinedText`) or WXXX (`UserDefinedURL`) frame whose own
    /// description field resolves — via `userDefinedFrameName`, the same logic exiftool itself
    /// uses to name these frames — to `tagName`. Mirrors `editableUserDefinedFrameNames`, which
    /// is what decided this tag was safe to offer for editing in the first place; re-resolving
    /// here (rather than trusting a stale index) means a file that changed on disk since it was
    /// read is still handled safely.
    private static func resolveUserDefinedFrame(tagName: String, frames: [Frame]) throws -> (frameID: String, index: Int) {
        var matches: [(frameID: String, index: Int)] = []
        for (index, frame) in frames.enumerated() {
            guard frame.id == "TXXX" || frame.id == "WXXX" else { continue }
            guard let name = try? userDefinedFrameName(frame), name == tagName else { continue }
            matches.append((frame.id, index))
        }
        guard matches.count == 1 else {
            throw matches.isEmpty ? WriterError.frameNotFound(tagName) : WriterError.ambiguousFrame(tagName)
        }
        return matches[0]
    }

    // MARK: - Rewriting

    private static func rewriteTextFrame(_ frame: Frame, newValue: String) throws -> Data {
        guard let originalEncoding = frame.data.first else { throw WriterError.invalidFrameData(frame.id) }
        var encoding = originalEncoding
        if encoding == 0 && !isLatin1Representable(newValue) {
            encoding = 1 // upgrade Latin-1 -> UTF-16 (with BOM); valid in both v2.3 and v2.4
        }
        return try Data([encoding]) + encodeText(encoding: encoding, value: newValue)
    }

    private static func rewriteCommentFrame(_ frame: Frame, newText: String) throws -> Data {
        try rewriteDescribedTextFrame(frame, prefixLength: 3, newValue: newText)
    }

    /// Shared by COMM (3-byte language prefix before the description) and TXXX (no prefix):
    /// both frames are [encoding][prefix][description][terminator][value], and only the value
    /// half ever changes here — the description, and which frame it identifies, stays untouched.
    private static func rewriteDescribedTextFrame(_ frame: Frame, prefixLength: Int, newValue: String) throws -> Data {
        guard frame.data.count >= 1 + prefixLength else { throw WriterError.invalidFrameData(frame.id) }
        let originalEncoding = frame.data[0]
        let prefix = frame.data.subdata(in: 1..<(1 + prefixLength))
        let rest = frame.data.subdata(in: (1 + prefixLength)..<frame.data.count)
        var (desc, _) = try splitDescriptionAndText(rest, encoding: originalEncoding, frameID: frame.id)

        var encoding = originalEncoding
        if encoding == 0 && !isLatin1Representable(newValue) {
            encoding = 1
            let descString = String(data: desc, encoding: .isoLatin1) ?? ""
            guard let utf16Desc = descString.data(using: .utf16) else { throw WriterError.cannotEncodeText }
            desc = utf16Desc
        }

        let term: Data = (encoding == 0 || encoding == 3) ? Data([0]) : Data([0, 0])
        let textBytes = try encodeText(encoding: encoding, value: newValue)
        return Data([encoding]) + prefix + desc + term + textBytes
    }

    /// Rewrites a WXXX frame's URL, leaving its description untouched. Unlike TXXX/COMM, the
    /// URL half is always Latin-1 and isn't null-terminated (it just runs to the end of the
    /// frame), matching how `Tag.parse`/exiftool itself read it.
    private static func rewriteUserURLFrame(_ frame: Frame, newValue: String) throws -> Data {
        guard let originalEncoding = frame.data.first else { throw WriterError.invalidFrameData(frame.id) }
        let rest = frame.data.subdata(in: 1..<frame.data.count)
        let (desc, _) = try splitDescriptionAndText(rest, encoding: originalEncoding, frameID: frame.id)
        guard let urlData = newValue.data(using: .isoLatin1) else { throw WriterError.cannotEncodeText }
        let term: Data = (originalEncoding == 0 || originalEncoding == 3) ? Data([0]) : Data([0, 0])
        return Data([originalEncoding]) + desc + term + urlData
    }

    // MARK: - User-defined (TXXX/WXXX) frame naming

    /// The exiftool tag name for a TXXX or WXXX frame, derived from its own description field
    /// the same way exiftool's ID3 module does (see `Image::ExifTool::ID3::ParseID3v2Frame`):
    /// an empty description falls back to the frame's generic name ("UserDefinedText"/
    /// "UserDefinedURL"); otherwise WXXX appends "_URL" to the description unless it already
    /// contains "url" (case-insensitively), and the result is run through the same
    /// illegal-character-stripping/capitalization exiftool's `MakeTagName` applies.
    private static func userDefinedFrameName(_ frame: Frame) throws -> String {
        guard let encoding = frame.data.first else { throw WriterError.invalidFrameData(frame.id) }
        let rest = frame.data.subdata(in: 1..<frame.data.count)
        let (descData, _) = try splitDescriptionAndText(rest, encoding: encoding, frameID: frame.id)
        guard let description = decodedString(descData, encoding: encoding) else {
            throw WriterError.invalidFrameData(frame.id)
        }
        if frame.id == "WXXX" {
            guard !description.isEmpty else { return "UserDefinedURL" }
            let source = description.range(of: "url", options: .caseInsensitive) != nil ? description : description + "_URL"
            return exifToolTagName(source)
        } else {
            guard !description.isEmpty else { return "UserDefinedText" }
            return exifToolTagName(description)
        }
    }

    private static func decodedString(_ data: Data, encoding: UInt8) -> String? {
        switch encoding {
        case 0: return String(data: data, encoding: .isoLatin1)
        case 1: return String(data: data, encoding: .utf16)
        case 2: return String(data: data, encoding: .utf16BigEndian)
        case 3: return String(data: data, encoding: .utf8)
        default: return nil
        }
    }

    /// Swift port of exiftool's `Image::ExifTool::MakeTagName`: keep only ASCII letters/digits/
    /// "-"/"_", capitalize the first character, and prefix "Tag" if that leaves fewer than two
    /// characters or one starting with "-" or a digit.
    private static func exifToolTagName(_ raw: String) -> String {
        var name = String(raw.filter { $0 == "-" || $0 == "_" || ($0.isASCII && $0.isLetter) || ($0.isASCII && $0.isNumber) })
        if let first = name.first {
            name.replaceSubrange(name.startIndex..<name.index(after: name.startIndex), with: String(first).uppercased())
        }
        if name.count < 2 || name.first == "-" || (name.first?.isASCII == true && name.first?.isNumber == true) {
            name = "Tag" + name
        }
        return name
    }

    private static func splitDescriptionAndText(_ rest: Data, encoding: UInt8, frameID: String = "COMM") throws -> (desc: Data, text: Data) {
        let bytes = [UInt8](rest)
        if encoding == 0 || encoding == 3 {
            guard let nullIndex = bytes.firstIndex(of: 0) else { throw WriterError.invalidFrameData(frameID) }
            return (Data(bytes[0..<nullIndex]), Data(bytes[(nullIndex + 1)...]))
        }
        // UTF-16 (with or without BOM): a real terminator is a double-zero at an even byte
        // offset from the start of this field, so a single zero byte that's really half of a
        // wide character doesn't get mistaken for one.
        var idx = 0
        while idx + 1 < bytes.count {
            if bytes[idx] == 0 && bytes[idx + 1] == 0 && idx % 2 == 0 {
                return (Data(bytes[0..<idx]), Data(bytes[(idx + 2)...]))
            }
            idx += 1
        }
        throw WriterError.invalidFrameData(frameID)
    }

    private static func rebuildTag(_ tag: Tag) throws -> Data {
        var body = Data()
        for frame in tag.frames {
            guard let idData = frame.id.data(using: .ascii), idData.count == 4 else {
                throw WriterError.invalidFrameID(frame.id)
            }
            let sizeData = tag.versionMajor == 4 ? syncsafeEncode(frame.data.count) : plainBEEncode(frame.data.count)
            let flagsData = Data([UInt8((frame.flags >> 8) & 0xff), UInt8(frame.flags & 0xff)])
            body += idData + sizeData + flagsData + frame.data
        }
        let newTagSize: Int
        if body.count <= tag.declaredBodySize {
            body += Data(repeating: 0, count: tag.declaredBodySize - body.count)
            newTagSize = tag.declaredBodySize
        } else {
            newTagSize = body.count
        }
        var header = Data([0x49, 0x44, 0x33, tag.versionMajor, 0, tag.headerFlags & 0x7f])
        header += syncsafeEncode(newTagSize)
        return header + body
    }

    // MARK: - Text encoding

    private static func isLatin1Representable(_ value: String) -> Bool {
        value.data(using: .isoLatin1) != nil
    }

    private static func encodeText(encoding: UInt8, value: String) throws -> Data {
        switch encoding {
        case 0:
            guard let data = value.data(using: .isoLatin1) else { throw WriterError.cannotEncodeText }
            return data + Data([0])
        case 1:
            guard let data = value.data(using: .utf16) else { throw WriterError.cannotEncodeText }
            // ".utf16" is documented to prepend a byte-order mark; verify rather than trust,
            // since a missing BOM here would silently produce a malformed frame on write.
            guard data.count >= 2, (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF) else {
                throw WriterError.cannotEncodeText
            }
            return data + Data([0, 0])
        case 2:
            guard let data = value.data(using: .utf16BigEndian) else { throw WriterError.cannotEncodeText }
            return data + Data([0, 0])
        case 3:
            guard let data = value.data(using: .utf8) else { throw WriterError.cannotEncodeText }
            return data + Data([0])
        default:
            throw WriterError.unknownTextEncoding(encoding)
        }
    }

    // MARK: - Integer encoding

    private static func syncsafeDecode(_ data: Data, at offset: Int) -> Int {
        (Int(data[offset]) << 21) | (Int(data[offset + 1]) << 14) | (Int(data[offset + 2]) << 7) | Int(data[offset + 3])
    }

    private static func syncsafeEncode(_ value: Int) -> Data {
        Data([
            UInt8((value >> 21) & 0x7f),
            UInt8((value >> 14) & 0x7f),
            UInt8((value >> 7) & 0x7f),
            UInt8(value & 0x7f),
        ])
    }

    private static func plainBEDecode(_ data: Data, at offset: Int) -> Int {
        (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16) | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
    }

    private static func plainBEEncode(_ value: Int) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ])
    }
}

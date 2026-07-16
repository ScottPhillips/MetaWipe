import Foundation

enum ExifToolError: LocalizedError {
    case binaryNotFound
    case processFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "exiftool was not found. Install it with \"brew install exiftool\"."
        case .processFailed(let message):
            return message
        case .invalidOutput:
            return "exiftool returned output that couldn't be parsed."
        }
    }
}

/// Thin wrapper around the exiftool CLI, which handles metadata for hundreds of file
/// formats (EXIF/IPTC/XMP for images, PDF/Office document properties, audio/video tags, etc.)
/// far more completely than Apple's per-format frameworks would let us reimplement here.
actor ExifToolBridge {
    static let shared = ExifToolBridge()

    private struct Invocation {
        let executable: URL
        let baseArguments: [String]
        let extraEnvironment: [String: String]
    }

    private var cachedWritableExtensions: Set<String>?

    /// Prefers the copy of exiftool + its Perl modules bundled in Contents/Resources so the
    /// app works standalone without Homebrew. Falls back to a Homebrew install for local
    /// development (e.g. running via `swift build` outside the .app bundle).
    private let invocation: Invocation? = {
        ExifToolBridge.bundledInvocation() ?? ExifToolBridge.systemInvocation()
    }()

    private static func bundledInvocation() -> Invocation? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let toolDir = resourceURL.appendingPathComponent("ExifTool")
        let scriptURL = toolDir.appendingPathComponent("exiftool")
        let libURL = toolDir.appendingPathComponent("lib")
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else { return nil }

        // exiftool ships pure-Perl modules directly under "lib" and architecture-specific
        // compiled ones under "lib/<archname>"; both need to be on Perl's search path.
        let archLibURL = libURL.appendingPathComponent("darwin-thread-multi-2level")
        let perl5lib = [libURL.path, archLibURL.path].joined(separator: ":")
        return Invocation(
            executable: URL(fileURLWithPath: "/usr/bin/perl"),
            baseArguments: [scriptURL.path],
            extraEnvironment: ["PERL5LIB": perl5lib]
        )
    }

    private static func systemInvocation() -> Invocation? {
        let candidates = ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return Invocation(executable: URL(fileURLWithPath: path), baseArguments: [], extraEnvironment: [:])
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> (stdout: Data, stderr: String, status: Int32) {
        guard let invocation else { throw ExifToolError.binaryNotFound }
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.baseArguments + arguments

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in invocation.extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdoutData, stderrString, process.terminationStatus)
    }

    /// Result of a metadata read: the tags themselves, plus whether exiftool can write
    /// this file's format at all (e.g. it can read ID3 tags from MP3 but never write them —
    /// see `writableFileExtensions`).
    struct ReadResult {
        let tags: [MetadataTag]
        let isFormatWritable: Bool
    }

    func readTags(url: URL) throws -> ReadResult {
        // "-G1" (family 1) reports the specific group each tag actually belongs to
        // (e.g. "IFD0", "ExifIFD", "XMP-dc", "ID3v2_3") rather than the family-0 summary
        // name ("EXIF", "XMP", "ID3"). Family-1 names double as the group specifier
        // exiftool expects when writing a tag back, so round-tripping a value through
        // "-\(group):\(name)=" only works reliably when we read groups this way.
        let result = try run(["-json", "-G1", "-a", "-u", "-struct", url.path])
        guard !result.stdout.isEmpty else {
            throw ExifToolError.processFailed(result.stderr.isEmpty ? "exiftool failed to read \(url.lastPathComponent)" : result.stderr)
        }
        guard
            let jsonArray = try JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]],
            let object = jsonArray.first
        else {
            throw ExifToolError.invalidOutput
        }

        var tags: [MetadataTag] = []
        var fileTypeExtension: String?
        for (key, rawValue) in object {
            guard key != "SourceFile" else { continue }
            let parts = key.split(separator: ":", maxSplits: 1)
            let group = parts.count > 1 ? String(parts[0]) : "File"
            let name = parts.count > 1 ? String(parts[1]) : key
            let value = Self.stringify(rawValue)
            tags.append(MetadataTag(id: key, group: group, name: name, value: value, originalValue: value))
            if name == "FileTypeExtension" {
                fileTypeExtension = value
            }
        }
        tags.sort {
            $0.group == $1.group ? $0.name < $1.name : $0.group < $1.group
        }

        let writableExtensions = try writableFileExtensions()
        let isFormatWritable = fileTypeExtension.map { writableExtensions.contains($0.uppercased()) } ?? false
        return ReadResult(tags: tags, isFormatWritable: isFormatWritable)
    }

    /// The file extensions exiftool is able to write, per its own "-listwf". Notably excludes
    /// formats it can only read — MP3/ID3 chief among them, which is why editing an MP3's tags
    /// always failed with "doesn't exist or isn't writable" regardless of which tag was touched.
    private func writableFileExtensions() throws -> Set<String> {
        if let cachedWritableExtensions { return cachedWritableExtensions }
        let result = try run(["-listwf"])
        guard let output = String(data: result.stdout, encoding: .utf8) else {
            throw ExifToolError.invalidOutput
        }
        let extensions = Set(
            output.split(whereSeparator: { $0.isWhitespace })
                .map { $0.uppercased() }
                .filter { $0 != "WRITABLE" && $0 != "FILE" && $0 != "EXTENSIONS:" }
        )
        cachedWritableExtensions = extensions
        return extensions
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] {
            return array.map { stringify($0) }.joined(separator: ", ")
        }
        if let dict = value as? [String: Any] {
            return dict.map { "\($0.key)=\(stringify($0.value))" }.joined(separator: "; ")
        }
        return String(describing: value)
    }

    /// Writes back only the tags the caller marks as edited. "-P" preserves the file's own
    /// modification date so a value tweak doesn't silently touch filesystem timestamps —
    /// that's a separate, explicit action in this app. "-overwrite_original_in_place" (rather
    /// than plain "-overwrite_original") matters here: exiftool's normal overwrite writes to a
    /// new temp file and renames it over the original, which silently drops extended
    /// attributes (Finder comments/tags, quarantine flag). The "_in_place" variant edits the
    /// existing inode so xattrs survive a plain tag edit — clearing them is a separate,
    /// explicit action in this app.
    func writeTags(url: URL, tags: [MetadataTag]) throws {
        let editable = tags.filter { $0.isEditable }
        guard !editable.isEmpty else { return }
        var arguments = editable.map { "-\($0.group):\($0.name)=\($0.value)" }
        arguments.append(contentsOf: ["-P", "-overwrite_original_in_place", url.path])
        let result = try run(arguments)
        guard result.status == 0 else {
            throw ExifToolError.processFailed(result.stderr.isEmpty ? "Failed to write tags" : result.stderr)
        }
    }

    /// Strips embedded metadata (EXIF/IPTC/XMP/MakerNotes/ICC profile/etc). When
    /// `keepBackup` is true, exiftool leaves the original bytes at "<name>_original".
    /// Uses the "_in_place" overwrite variant so this doesn't also wipe extended attributes
    /// as a side effect — see the note on `writeTags`. Erasing xattrs is its own toggle,
    /// handled separately by `XattrManager`.
    func eraseAll(url: URL, keepBackup: Bool) throws {
        var arguments = ["-all=", "-icc_profile=", "-P"]
        if !keepBackup {
            arguments.append("-overwrite_original_in_place")
        }
        arguments.append(url.path)
        let result = try run(arguments)
        guard result.status == 0 else {
            throw ExifToolError.processFailed(result.stderr.isEmpty ? "Failed to erase metadata" : result.stderr)
        }
    }
}

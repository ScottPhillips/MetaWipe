import Foundation
import Darwin

enum XattrError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// macOS extended attributes: Finder comments/tags, the download quarantine flag,
/// "where from" URLs, and similar sidecar data that lives outside the file's own bytes.
enum XattrManager {
    static func list(url: URL) throws -> [XattrEntry] {
        try listNames(url: url).map { name in
            XattrEntry(name: name, sizeBytes: sizeOfAttribute(url: url, name: name))
        }
    }

    static func remove(url: URL, name: String) throws {
        guard removexattr(url.path, name, XATTR_NOFOLLOW) == 0 else {
            throw XattrError.failed("Couldn't remove \"\(name)\": \(String(cString: strerror(errno)))")
        }
    }

    static func clearAll(url: URL) throws {
        var firstError: Error?
        for name in try listNames(url: url) {
            do {
                try remove(url: url, name: name)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private static func listNames(url: URL) throws -> [String] {
        let path = url.path
        let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: size)
        let result = listxattr(path, &buffer, size, XATTR_NOFOLLOW)
        guard result > 0 else { return [] }

        var names: [String] = []
        var current: [CChar] = []
        for i in 0..<result {
            let c = buffer[i]
            if c == 0 {
                if !current.isEmpty {
                    current.append(0)
                    names.append(String(cString: current))
                    current = []
                }
            } else {
                current.append(c)
            }
        }
        return names
    }

    private static func sizeOfAttribute(url: URL, name: String) -> Int {
        max(0, getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW))
    }
}

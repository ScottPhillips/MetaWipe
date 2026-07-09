import AppKit

/// Backs the two Finder → right-click → Services entries declared in Info.plist
/// (NSServices): "Strip Meta Tags" and "Edit Meta Tags". Selector names must match
/// each entry's NSMessage exactly.
final class FinderServiceProvider: NSObject {
    @objc func stripMetaTags(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty else {
            error.pointee = "MetaWipe couldn't find any files to strip." as NSString
            return
        }
        Task { @MainActor in
            for url in urls {
                do {
                    try await ExifToolBridge.shared.eraseAll(url: url, keepBackup: true)
                    try XattrManager.clearAll(url: url)
                } catch {
                    NSLog("MetaWipe: failed to strip metadata from \(url.path): \(error)")
                }
            }
        }
    }

    @objc func editMetaTags(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty else {
            error.pointee = "MetaWipe couldn't find any files to open." as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .metaWipeAddFiles, object: nil, userInfo: ["urls": urls])
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    }
}

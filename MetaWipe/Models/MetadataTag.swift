import Foundation

struct MetadataTag: Identifiable, Equatable {
    /// The exiftool "Group:TagName" key, which is also what we write back with.
    let id: String
    let group: String
    let name: String
    var value: String
    let originalValue: String

    var isModified: Bool { value != originalValue }

    /// Groups exiftool computes or reads from the filesystem rather than storing
    /// in the file itself — editing these through exiftool would fail or be meaningless.
    var isEditable: Bool {
        !Self.readOnlyGroups.contains(group)
    }

    /// With tags read via "-G1" (see ExifToolBridge.readTags), filesystem-derived tags split
    /// across two family-1 groups depending on the tag ("System" for FileName/FileSize/dates,
    /// "File" for FileType/MIMEType/etc.) — both are exiftool-computed, not stored in the file.
    private static let readOnlyGroups: Set<String> = ["File", "System", "Composite", "ExifTool"]
}

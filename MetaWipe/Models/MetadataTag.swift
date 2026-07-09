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

    private static let readOnlyGroups: Set<String> = ["File", "Composite", "ExifTool"]
}

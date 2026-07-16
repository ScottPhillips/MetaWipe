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
    ///
    /// ID3v2_3/ID3v2_4 (MP3) are a special case: exiftool can't write MP3 at all, so those
    /// tags are only editable through `ID3Writer`'s narrow set of supported frames (see
    /// `ID3TextFrameNames`) — everything else under those groups, and every other ID3-family
    /// group (ID3v1, ID3v1_Enh, ID3v2_2, Lyrics3, and the generic "ID3" group used for
    /// PRIV/GEOB/etc.), stays read-only since nothing in this app can write them.
    var isEditable: Bool {
        guard !Self.readOnlyGroups.contains(group) else { return false }
        switch group {
        case "ID3v2_3", "ID3v2_4":
            return ID3TextFrameNames.frameIDsByTagName[name] != nil
        case "ID3", "ID3v1", "ID3v1_Enh", "ID3v2_2", "Lyrics3":
            return false
        default:
            return true
        }
    }

    /// With tags read via "-G1" (see ExifToolBridge.readTags), filesystem-derived tags split
    /// across two family-1 groups depending on the tag ("System" for FileName/FileSize/dates,
    /// "File" for FileType/MIMEType/etc.) — both are exiftool-computed, not stored in the file.
    private static let readOnlyGroups: Set<String> = ["File", "System", "Composite", "ExifTool"]
}

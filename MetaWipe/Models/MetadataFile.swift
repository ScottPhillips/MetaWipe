import Foundation

@MainActor
final class MetadataFile: ObservableObject, Identifiable, Hashable {
    let id = UUID()
    let url: URL

    @Published var tags: [MetadataTag] = []
    @Published var xattrs: [XattrEntry] = []
    @Published var creationDate: Date?
    @Published var modificationDate: Date?
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var lastAction: String?
    /// Whether *something* (exiftool or, for MP3, `ID3Writer`) can write this file's format
    /// at all. Gates whether tag values are shown as editable.
    @Published var isFormatWritable = true
    /// Lowercase/uppercase-insensitive file type extension as exiftool detects it (from file
    /// content, not just the path extension) — used to route saves to the right writer.
    @Published var fileTypeExtension: String?

    init(url: URL) {
        self.url = url
    }

    var name: String { url.lastPathComponent }

    nonisolated static func == (lhs: MetadataFile, rhs: MetadataFile) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

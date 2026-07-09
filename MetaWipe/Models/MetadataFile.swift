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

    init(url: URL) {
        self.url = url
    }

    var name: String { url.lastPathComponent }

    nonisolated static func == (lhs: MetadataFile, rhs: MetadataFile) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

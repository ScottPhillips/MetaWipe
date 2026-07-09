import Foundation

struct XattrEntry: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let sizeBytes: Int
}

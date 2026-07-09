import Foundation

enum FileTimestampError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

enum FileTimestampManager {
    struct Dates {
        let creation: Date?
        let modification: Date?
    }

    static func dates(url: URL) throws -> Dates {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return Dates(creation: values.creationDate, modification: values.contentModificationDate)
    }

    static func setDates(url: URL, creation: Date, modification: Date) throws {
        let attributes: [FileAttributeKey: Any] = [
            .creationDate: creation,
            .modificationDate: modification
        ]
        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            throw FileTimestampError.failed(error.localizedDescription)
        }
    }

    static func resetToNow(url: URL) throws {
        let now = Date()
        try setDates(url: url, creation: now, modification: now)
    }
}

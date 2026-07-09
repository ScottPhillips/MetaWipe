import Foundation

struct ReleaseInfo {
    let version: String
    let htmlURL: URL
}

enum UpdateCheckError: LocalizedError {
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return message
        case .invalidResponse:
            return "Couldn't read release information from GitHub."
        }
    }
}

enum UpdateChecker {
    private static let releasesURL = URL(string: "https://api.github.com/repos/ScottPhillips/MetaWipe/releases/latest")!

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw UpdateCheckError.network("GitHub returned an unexpected response.")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String,
            let htmlURLString = json["html_url"] as? String,
            let htmlURL = URL(string: htmlURLString)
        else {
            throw UpdateCheckError.invalidResponse
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return ReleaseInfo(version: version, htmlURL: htmlURL)
    }

    /// Compares dot-separated numeric versions component-by-component (e.g. "1.10.0" > "1.9.3"),
    /// since plain string comparison would get that case backwards.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(latestParts.count, currentParts.count)
        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l != c { return l > c }
        }
        return false
    }
}

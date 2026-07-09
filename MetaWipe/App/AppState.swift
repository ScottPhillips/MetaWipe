import Foundation

struct UpdateAlert: Identifiable {
    enum Kind {
        case updateAvailable(version: String, url: URL)
        case upToDate
        case failed(String)
    }
    let id = UUID()
    let kind: Kind
}

@MainActor
final class AppState: ObservableObject {
    @Published var files: [MetadataFile] = []
    @Published var selectedFileID: MetadataFile.ID?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var updateAlert: UpdateAlert?

    var selectedFile: MetadataFile? {
        files.first { $0.id == selectedFileID }
    }

    /// Checks the GitHub releases API for a newer tagged version than this build.
    /// `silent: true` (used on launch) only surfaces UI when an update is actually found;
    /// `silent: false` (the manual "Check for Updates…" command) always reports a result.
    func checkForUpdates(silent: Bool) async {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        do {
            let release = try await UpdateChecker.fetchLatestRelease()
            if UpdateChecker.isNewer(release.version, than: currentVersion) {
                updateAlert = UpdateAlert(kind: .updateAvailable(version: release.version, url: release.htmlURL))
            } else if !silent {
                updateAlert = UpdateAlert(kind: .upToDate)
            }
        } catch {
            if !silent {
                updateAlert = UpdateAlert(kind: .failed(error.localizedDescription))
            }
        }
    }

    func addFiles(_ urls: [URL]) {
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            let file = MetadataFile(url: url)
            files.append(file)
            if selectedFileID == nil { selectedFileID = file.id }
            Task { await load(file) }
        }
    }

    func removeFile(_ file: MetadataFile) {
        files.removeAll { $0.id == file.id }
        if selectedFileID == file.id { selectedFileID = files.first?.id }
    }

    func load(_ file: MetadataFile) async {
        file.isLoading = true
        file.loadError = nil
        defer { file.isLoading = false }
        do {
            let tags = try await ExifToolBridge.shared.readTags(url: file.url)
            let xattrs = try XattrManager.list(url: file.url)
            let dates = try FileTimestampManager.dates(url: file.url)
            file.tags = tags
            file.xattrs = xattrs
            file.creationDate = dates.creation
            file.modificationDate = dates.modification
        } catch {
            file.loadError = error.localizedDescription
        }
    }

    func saveTagEdits(_ file: MetadataFile) async {
        let modified = file.tags.filter { $0.isModified }
        guard !modified.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ExifToolBridge.shared.writeTags(url: file.url, tags: modified)
            file.lastAction = "Saved \(modified.count) tag change(s)"
            await load(file)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveTimestampEdits(_ file: MetadataFile) async {
        guard let creation = file.creationDate, let modification = file.modificationDate else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try FileTimestampManager.setDates(url: file.url, creation: creation, modification: modification)
            file.lastAction = "Timestamps updated"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func eraseMetadata(_ file: MetadataFile, options: EraseOptions) async {
        isBusy = true
        defer { isBusy = false }
        var errors: [String] = []

        if options.embedded {
            do {
                try await ExifToolBridge.shared.eraseAll(url: file.url, keepBackup: options.keepBackup)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if options.xattrs {
            do {
                try XattrManager.clearAll(url: file.url)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if options.timestamps {
            do {
                try FileTimestampManager.resetToNow(url: file.url)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        file.lastAction = errors.isEmpty ? "Metadata erased" : "Erased with issues"
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
        await load(file)
    }
}

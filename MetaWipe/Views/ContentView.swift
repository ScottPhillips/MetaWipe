import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                }
                .overlay {
                    if appState.files.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.badge.gearshape")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Drop files here")
                                .foregroundStyle(.secondary)
                            Button("Add Files…") { presentOpenPanel() }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    }
                }
        } detail: {
            if let file = appState.selectedFile {
                MetadataDetailView(file: file)
                    .id(file.id)
            } else {
                Text("Select a file")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentOpenPanel()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .metaWipeAddFiles)) { notification in
            if let urls = notification.userInfo?["urls"] as? [URL] {
                appState.addFiles(urls)
            } else {
                presentOpenPanel()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert(
            "Software Update",
            isPresented: Binding(
                get: { appState.updateAlert != nil },
                set: { if !$0 { appState.updateAlert = nil } }
            ),
            presenting: appState.updateAlert
        ) { alert in
            switch alert.kind {
            case .updateAvailable(_, let url):
                Button("View Release") { NSWorkspace.shared.open(url) }
                Button("Later", role: .cancel) {}
            case .upToDate, .failed:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            switch alert.kind {
            case .updateAvailable(let version, _):
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                Text("MetaWipe \(version) is available. You have \(current).")
            case .upToDate:
                Text("You're using the latest version of MetaWipe.")
            case .failed(let message):
                Text(message)
            }
        }
        .task {
            await appState.checkForUpdates(silent: true)
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Files"
        if panel.runModal() == .OK {
            appState.addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            appState.addFiles(urls)
        }
        return true
    }
}

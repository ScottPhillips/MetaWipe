import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedFileID },
            set: { appState.requestSelection($0) }
        )) {
            ForEach(appState.files) { file in
                FileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
                        Button("Reload Tags") {
                            Task { await appState.load(file) }
                        }
                        Button("Remove", role: .destructive) {
                            appState.removeFile(file)
                        }
                    }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    appState.removeFile(appState.files[index])
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Files")
        .alert("Unsaved Changes", isPresented: $appState.showUnsavedChangesPrompt) {
            Button("Discard Changes", role: .destructive) {
                appState.confirmDiscardAndSwitch()
            }
            Button("Cancel", role: .cancel) {
                appState.cancelPendingSwitch()
            }
        } message: {
            Text("\(appState.selectedFile?.name ?? "This file") has unsaved tag edits. Switching files will discard them.")
        }
    }
}

private struct FileRow: View {
    @ObservedObject var file: MetadataFile

    var body: some View {
        HStack {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                if let error = file.loadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if file.isLoading {
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(file.tags.count) tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedFileID },
            set: { appState.selectedFileID = $0 }
        )) {
            ForEach(appState.files) { file in
                FileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
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

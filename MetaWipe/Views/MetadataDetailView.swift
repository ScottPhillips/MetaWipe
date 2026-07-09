import SwiftUI

struct MetadataDetailView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var file: MetadataFile
    @State private var searchText = ""
    @State private var showEraseSheet = false

    private var filteredTagIDs: Set<String> {
        guard !searchText.isEmpty else { return Set(file.tags.map(\.id)) }
        return Set(file.tags.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.group.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText)
        }.map(\.id))
    }

    private var hasUnsavedChanges: Bool {
        file.tags.contains { $0.isModified }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showEraseSheet) {
            EraseConfirmationView(file: file, isPresented: $showEraseSheet)
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if file.isLoading {
            ProgressView("Reading metadata…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = file.loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(error)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await appState.load(file) } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            let visibleIDs = filteredTagIDs
            List {
                Section("Metadata Tags (\(visibleIDs.count))") {
                    ForEach($file.tags) { $tag in
                        if visibleIDs.contains(tag.id) {
                            TagRow(tag: $tag)
                        }
                    }
                }
                Section("Extended Attributes (\(file.xattrs.count))") {
                    if file.xattrs.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(file.xattrs) { attr in
                        HStack {
                            Text(attr.name).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("\(attr.sizeBytes) bytes").foregroundStyle(.secondary)
                            Button {
                                Task { await removeXattr(attr) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section("File Timestamps") {
                    DatePicker("Created", selection: creationBinding, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Modified", selection: modificationBinding, displayedComponents: [.date, .hourAndMinute])
                    Button("Save Timestamps") {
                        Task { await appState.saveTimestampEdits(file) }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter tags")
            .listStyle(.inset)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.headline)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let action = file.lastAction {
                    Text(action).font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            if hasUnsavedChanges {
                Button("Save Changes") {
                    Task { await appState.saveTagEdits(file) }
                }
                .disabled(appState.isBusy)
            }
            Button(role: .destructive) {
                showEraseSheet = true
            } label: {
                Label("Erase All Metadata", systemImage: "trash")
            }
            .disabled(appState.isBusy)
        }
        .padding()
    }

    private var creationBinding: Binding<Date> {
        Binding(
            get: { file.creationDate ?? Date() },
            set: { file.creationDate = $0 }
        )
    }

    private var modificationBinding: Binding<Date> {
        Binding(
            get: { file.modificationDate ?? Date() },
            set: { file.modificationDate = $0 }
        )
    }

    private func removeXattr(_ attr: XattrEntry) async {
        do {
            try XattrManager.remove(url: file.url, name: attr.name)
            file.xattrs.removeAll { $0.id == attr.id }
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

private struct TagRow: View {
    @Binding var tag: MetadataTag

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name).font(.body)
                Text(tag.group).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .leading)
            if tag.isEditable {
                TextField("Value", text: $tag.value)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(tag.value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

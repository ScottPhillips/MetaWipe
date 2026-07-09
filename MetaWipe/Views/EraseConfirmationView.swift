import SwiftUI

struct EraseConfirmationView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var file: MetadataFile
    @Binding var isPresented: Bool

    @State private var eraseEmbedded = true
    @State private var eraseXattrs = true
    @State private var eraseTimestamps = false
    @State private var keepBackup = true
    @State private var isErasing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Erase All Metadata", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)

            Text("This permanently removes metadata from \"\(file.name)\". Choose what to erase:")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Embedded metadata (EXIF, IPTC, XMP, GPS, ICC profile, etc.)", isOn: $eraseEmbedded)
                Toggle("Extended attributes (Finder tags, comments, quarantine flag)", isOn: $eraseXattrs)
                Toggle("Filesystem timestamps (reset created/modified to now)", isOn: $eraseTimestamps)
            }

            Divider()

            Toggle("Keep a backup copy of the original (adds \"_original\")", isOn: $keepBackup)
                .disabled(!eraseEmbedded)

            Text(warningText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    erase()
                } label: {
                    if isErasing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Erase")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isErasing || (!eraseEmbedded && !eraseXattrs && !eraseTimestamps))
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var warningText: String {
        if keepBackup && eraseEmbedded {
            return "This action cannot be undone, except by restoring the backup copy exiftool leaves alongside the file."
        }
        return "This action cannot be undone."
    }

    private func erase() {
        isErasing = true
        let options = EraseOptions(embedded: eraseEmbedded, xattrs: eraseXattrs, timestamps: eraseTimestamps, keepBackup: keepBackup)
        Task {
            await appState.eraseMetadata(file, options: options)
            isErasing = false
            isPresented = false
        }
    }
}

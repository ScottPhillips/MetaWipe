import SwiftUI

@main
struct MetaWipeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") {
                    NotificationCenter.default.post(name: .metaWipeAddFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let metaWipeAddFiles = Notification.Name("metaWipeAddFiles")
}

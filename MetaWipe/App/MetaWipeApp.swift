import SwiftUI
import AppKit

private let githubURL = URL(string: "https://github.com/ScottPhillips/MetaWipe")!

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let finderServiceProvider = FinderServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = finderServiceProvider
        NSUpdateDynamicServices()
    }
}

@main
struct MetaWipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            CommandGroup(replacing: .appInfo) {
                Button("About MetaWipe") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: githubURL.absoluteString,
                            attributes: [
                                .link: githubURL,
                                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                            ]
                        )
                    ])
                }
                Button("Check for Updates…") {
                    Task { await appState.checkForUpdates(silent: false) }
                }
            }
        }
    }
}

extension Notification.Name {
    static let metaWipeAddFiles = Notification.Name("metaWipeAddFiles")
}

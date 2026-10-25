import AppKit
import SwiftUI

@main
struct MahzenApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // A single window: opening an .exe from Finder must not spawn extra windows.
        Window("Mahzen", id: "main") {
            ContentView()
                .environment(delegate.store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") { delegate.store.showingNewBottle = true }
                    .keyboardShortcut("n")
                    .disabled(delegate.store.engines.isEmpty)
            }
        }

        Settings {
            EnginesView()
                .environment(delegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()

    /// "Open With → Mahzen" on an .exe/.msi in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        store.pendingOpen += urls.filter { ["exe", "msi"].contains($0.pathExtension.lowercased()) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

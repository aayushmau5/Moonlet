import SwiftUI

@main
struct MoonletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Moonlet", systemImage: "moon.circle") {
            Button("Quit Moonlet") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

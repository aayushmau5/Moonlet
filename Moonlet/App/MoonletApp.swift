import SwiftUI

@main
struct MoonletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Moonlet", systemImage: "moon.circle") {
            MenuPanel(appState: appDelegate.appState, audio: appDelegate.audio)
        }
        .menuBarExtraStyle(.window)
    }
}

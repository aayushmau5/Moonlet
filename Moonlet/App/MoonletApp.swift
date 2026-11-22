import SwiftUI

@main
struct MoonletApp: App {
    static let settingsWindowID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Moonlet", systemImage: "moon.circle") {
            MenuPanel(appState: appDelegate.appState, audio: appDelegate.audio)
        }
        .menuBarExtraStyle(.window)

        Window("Moonlet Settings", id: Self.settingsWindowID) {
            SettingsWindow(
                appState: appDelegate.appState,
                audio: appDelegate.audio,
                loginItem: appDelegate.loginItem,
                thumbnails: appDelegate.thumbnails
            )
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

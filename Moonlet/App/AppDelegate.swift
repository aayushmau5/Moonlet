import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "app")
    let appState = AppState()
    private var desktop: DesktopWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        let desktop = DesktopWindowController(displayProvider: SystemDisplayProvider())
        desktop.start()
        self.desktop = desktop

        let url = appState.currentVideoURL
        let renderer = VideoRenderer(url: url)
        Task {
            do {
                try await renderer.load()
                desktop.show(renderer)
                logger.info("Playing \(url.path, privacy: .public)")
            } catch {
                logger.error("Could not load \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktop?.closeAll()
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

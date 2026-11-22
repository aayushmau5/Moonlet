import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private let desktop: DesktopWindowController

    override init() {
        let desktop = DesktopWindowController(displayProvider: SystemDisplayProvider())
        self.desktop = desktop
        self.appState = AppState(library: Library(), switcher: WallpaperSwitcher(desktop: desktop))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        desktop.start()
        appState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.library.stopWatching()
        desktop.closeAll()
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

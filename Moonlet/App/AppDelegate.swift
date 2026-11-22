import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let audio: AudioController
    private let desktop: DesktopWindowController
    private let switcher: WallpaperSwitcher
    private let otherAudio = OtherAudioDetector(monitor: PlaybackMonitor(ignoredBundleIDs: PlaybackMonitor.savedIgnoreList()))
    private let system = SystemMonitor()

    override init() {
        let library = Library()
        let desktop = DesktopWindowController(displayProvider: SystemDisplayProvider())
        let switcher = WallpaperSwitcher(desktop: desktop)
        self.desktop = desktop
        self.switcher = switcher
        self.appState = AppState(library: library, switcher: switcher)
        self.audio = AudioController(library: library)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        switcher.onShown = { [audio] wallpaper in
            audio.wallpaperShown(wallpaper)
        }
        appState.library.addChangeHandler { [audio] in
            audio.libraryChanged()
        }
        otherAudio.onChange = { [audio] app in
            audio.setOtherAudio(app)
        }
        system.onChange = { [audio] text in
            audio.setSystemPause(text)
        }

        desktop.start()
        appState.start()
        startMusicWithoutWaitingIfNeeded()
        otherAudio.start()
        system.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.library.stopWatching()
        desktop.closeAll()
    }

    private func startMusicWithoutWaitingIfNeeded() {
        guard appState.selectedWallpaperID != nil else {
            audio.start(wallpaper: nil)
            return
        }
        Task { [audio] in
            try? await Task.sleep(for: .seconds(5))
            if !audio.isStarted {
                audio.start(wallpaper: nil)
            }
        }
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let audio: AudioController
    private let desktop: DesktopWindowController
    private let switcher: WallpaperSwitcher
    private let otherAudio = OtherAudioDetector(monitor: PlaybackMonitor(ignoredBundleIDs: PlaybackMonitor.savedIgnoreList()))
    private let system = SystemMonitor()
    private var visibility: VisibilityMonitor?
    private var coveredDisplays: Set<CGDirectDisplayID> = []
    private var isSystemPaused = false

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
        system.addChangeHandler { [audio] text in
            audio.setSystemPause(text)
        }
        system.addChangeHandler { [weak self] text in
            self?.isSystemPaused = text != nil
            self?.updateVisualPause()
        }
        let visibility = VisibilityMonitor(displayProvider: SystemDisplayProvider()) { [desktop] displayID in
            guard let window = desktop.windows[displayID] else { return false }
            return !window.occlusionState.contains(.visible)
        }
        visibility.onChange = { [weak self] covered in
            self?.coveredDisplays = covered
            self?.updateVisualPause()
        }
        self.visibility = visibility

        desktop.start()
        appState.start()
        startMusicWithoutWaitingIfNeeded()
        otherAudio.start()
        system.start()
        visibility.start()
    }

    private func updateVisualPause() {
        let paused = isSystemPaused ? Set(desktop.windows.keys) : coveredDisplays
        desktop.setPausedDisplays(paused)
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

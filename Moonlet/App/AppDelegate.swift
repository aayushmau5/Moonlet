import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let audio: AudioController
    let loginItem = LoginItem()
    let thumbnails = Thumbnails()
    let ignoreList = IgnoreList()
    private let desktop: DesktopWindowController
    private let switcher: WallpaperSwitcher
    private let otherAudio = OtherAudioDetector(monitor: PlaybackMonitor(ignoredBundleIDs: PlaybackMonitor.savedIgnoreList()))
    private let system = SystemMonitor()
    private let lowPower = LowPowerMonitor()
    private var visibility: VisibilityMonitor?
    private let desktopPicture = DesktopPicture()
    private var stillTask: Task<Void, Never>?
    private var coveredStillTask: Task<Void, Never>?
    private var screensNeedingStill: Set<CGDirectDisplayID> = []
    private var isSystemPaused = false

    override init() {
        let library = Library(rootURL: Library.savedRootURL())
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

        switcher.onShown = { [weak self, audio] wallpaper in
            audio.wallpaperShown(wallpaper)
            self?.wallpaperShown()
        }
        appState.library.addChangeHandler { [audio] in
            audio.libraryChanged()
        }
        otherAudio.onChange = { [audio] app in
            audio.setOtherAudio(app)
        }
        ignoreList.onChange = { [otherAudio] bundleIDs in
            otherAudio.setIgnoredBundleIDs(bundleIDs)
        }
        appState.onWallpaperPauseChange = { [weak self] in
            guard let self else { return }
            updateVisualPause()
            if appState.isWallpaperUserPaused {
                updateDesktopPicture()
            } else {
                stillTask?.cancel()
                screensNeedingStill = Set(desktop.windows.keys)
                if desktop.isParked {
                    switcher.replay()
                }
            }
        }
        appState.onAutoPauseChange = { [weak self] in
            self?.updateVisualPause()
            self?.captureStillsOnPausedScreens()
        }
        lowPower.onChange = { [weak self] enabled in
            self?.appState.setLowPowerMode(enabled)
        }
        system.addChangeHandler { [audio] text in
            audio.setSystemPause(text)
        }
        system.addChangeHandler { [weak self] text in
            self?.isSystemPaused = text != nil
            self?.updateVisualPause()
            self?.captureStillsOnPausedScreens()
        }
        let visibility = VisibilityMonitor(displayProvider: SystemDisplayProvider()) { [desktop] displayID in
            guard let window = desktop.windows[displayID] else { return false }
            return !window.occlusionState.contains(.visible)
        }
        visibility.onChange = { [weak self] covered in
            self?.appState.setCoveredDisplays(covered)
            self?.updateVisualPause()
            self?.captureStillsOnPausedScreens()
        }
        self.visibility = visibility

        desktop.setWallpaperPaused(appState.isWallpaperUserPaused)
        desktop.start()
        desktopPicture.start()
        appState.start()
        startMusicWithoutWaitingIfNeeded()
        otherAudio.start()
        system.start()
        lowPower.start()
        visibility.start()
    }

    private func updateVisualPause() {
        let pausesEveryScreen = isSystemPaused || appState.isLowPowerPausing
        let paused = pausesEveryScreen ? Set(desktop.windows.keys) : appState.pausedCoveredDisplays
        desktop.setPausedDisplays(paused)
        desktop.setWallpaperPaused(appState.isWallpaperUserPaused)
    }

    private func wallpaperShown() {
        if appState.isWallpaperUserPaused || desktop.isParked {
            updateDesktopPicture()
        } else {
            screensNeedingStill = Set(desktop.windows.keys)
            captureStillsOnPausedScreens()
        }
    }

    private func captureStillsOnPausedScreens() {
        let ready = screensNeedingStill.intersection(desktop.pausedDisplays)
        guard !ready.isEmpty, !appState.isWallpaperUserPaused else { return }
        screensNeedingStill.subtract(ready)
        coveredStillTask = Task { [weak self, previous = coveredStillTask] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            let stills = await desktop.stills(on: ready)
            guard !Task.isCancelled else { return }
            await desktopPicture.show(stills)
        }
    }

    private func updateDesktopPicture() {
        screensNeedingStill.removeAll()
        coveredStillTask?.cancel()
        stillTask?.cancel()
        stillTask = Task { [weak self] in
            guard let self else { return }
            let stills = await desktop.stills()
            guard !Task.isCancelled else { return }
            await desktopPicture.show(stills)
            guard !Task.isCancelled else { return }
            let hasEveryScreen = !stills.isEmpty && stills.count == desktop.windows.count
            guard appState.isWallpaperUserPaused, hasEveryScreen else { return }
            await desktop.park(showing: stills, duration: 0.6)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.library.stopWatching()
        desktopPicture.stop()
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

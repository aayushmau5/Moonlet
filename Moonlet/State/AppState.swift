import CoreGraphics
import Foundation
import Observation

struct WallpaperRemovalError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
@Observable
final class AppState {
    static let selectedWallpaperKey = "selectedWallpaperID"
    static let selectedPackKey = "selectedPackID"
    static let wallpaperPausedKey = "wallpaperPaused"
    static let pausesInLowPowerModeKey = "pausesInLowPowerMode"

    let library: Library
    private(set) var selectedWallpaperID: String?
    private(set) var selectedPackID: String?
    private(set) var isWallpaperUserPaused: Bool
    private(set) var coveredDisplays: Set<CGDirectDisplayID> = []
    private(set) var isCoverOverridden = false
    private(set) var pausesInLowPowerMode: Bool
    private(set) var isLowPowerMode = false
    private(set) var isLowPowerOverridden = false

    @ObservationIgnored var onWallpaperPauseChange: (() -> Void)?
    @ObservationIgnored var onAutoPauseChange: (() -> Void)?

    @ObservationIgnored let scheduler: PackScheduler
    @ObservationIgnored private let switcher: WallpaperSwitching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isSupported: @MainActor (WallpaperKind) -> Bool
    @ObservationIgnored private let removeItem: (URL) throws -> Void

    init(
        library: Library,
        switcher: WallpaperSwitching,
        defaults: UserDefaults = .standard,
        scheduler: PackScheduler = PackScheduler(),
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        isSupported: @escaping @MainActor (WallpaperKind) -> Bool = RendererFactory.supports
    ) {
        self.library = library
        self.switcher = switcher
        self.defaults = defaults
        self.scheduler = scheduler
        self.isSupported = isSupported
        self.removeItem = removeItem
        self.selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        self.selectedPackID = defaults.string(forKey: Self.selectedPackKey)
        self.isWallpaperUserPaused = defaults.bool(forKey: Self.wallpaperPausedKey)
        self.pausesInLowPowerMode = defaults.object(forKey: Self.pausesInLowPowerModeKey) as? Bool ?? true
    }

    var problems: [Problem] {
        (library.problems + switcher.problems).sorted { $0.location < $1.location }
    }

    func supports(_ wallpaper: Wallpaper) -> Bool {
        isSupported(wallpaper.kind)
    }

    func start(watching: Bool = true) {
        scheduler.onWallpaper = { [weak self] id in
            self?.show(id)
        }
        library.addChangeHandler { [weak self] in
            self?.libraryDidChange()
        }
        library.scan()
        if watching {
            library.startWatching()
            scheduler.start()
        }
    }

    func select(_ id: String) {
        guard let wallpaper = library.wallpaper(withID: id), supports(wallpaper) else { return }
        stopPack()
        remember(id)
        switcher.switchTo(wallpaper)
    }

    var isWallpaperPaused: Bool {
        isWallpaperUserPaused || isCoverPausing || isLowPowerPausing
    }

    var isLowPowerPausing: Bool {
        pausesInLowPowerMode && isLowPowerMode && !isLowPowerOverridden
    }

    var pausedCoveredDisplays: Set<CGDirectDisplayID> {
        isCoverOverridden ? [] : coveredDisplays
    }

    private var isCoverPausing: Bool {
        !coveredDisplays.isEmpty && !isCoverOverridden
    }

    func toggleWallpaperPause() {
        if isWallpaperPaused {
            isWallpaperUserPaused = false
            if isCoverPausing {
                isCoverOverridden = true
            }
            if isLowPowerPausing {
                isLowPowerOverridden = true
            }
        } else {
            isWallpaperUserPaused = true
        }
        defaults.set(isWallpaperUserPaused, forKey: Self.wallpaperPausedKey)
        onWallpaperPauseChange?()
    }

    func setCoveredDisplays(_ displays: Set<CGDirectDisplayID>) {
        if displays.isEmpty {
            isCoverOverridden = false
        }
        coveredDisplays = displays
    }

    func setLowPowerMode(_ enabled: Bool) {
        if !enabled {
            isLowPowerOverridden = false
        }
        isLowPowerMode = enabled
        onAutoPauseChange?()
    }

    func setPausesInLowPowerMode(_ enabled: Bool) {
        pausesInLowPowerMode = enabled
        isLowPowerOverridden = false
        defaults.set(enabled, forKey: Self.pausesInLowPowerModeKey)
        onAutoPauseChange?()
    }

    func moveLibrary(to folder: URL) {
        defaults.set(folder.path, forKey: Library.rootPathKey)
        library.relocate(to: folder)
        if let id = selectedPackID, library.pack(withID: id) == nil {
            stopPack()
        }
        let current = selectedWallpaperID.flatMap(library.wallpaper(withID:))
        if current == nil, let first = library.wallpapers.first(where: supports) {
            select(first.id)
        }
    }

    func moveToTrash(_ id: String) throws {
        guard let wallpaper = library.wallpaper(withID: id) else {
            throw WallpaperRemovalError(message: "\(id) is not in the library")
        }
        try removeItem(wallpaper.folder)
        library.scan()
        if selectedPackID == nil, selectedWallpaperID == id,
           let next = library.wallpapers.first(where: supports) {
            select(next.id)
        }
    }

    func rename(_ id: String, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw WallpaperRemovalError(message: "A wallpaper name can't be empty")
        }
        guard let wallpaper = library.wallpaper(withID: id) else {
            throw WallpaperRemovalError(message: "\(id) is not in the library")
        }
        let file = wallpaper.folder.appending(path: WallpaperManifestParser.fileName)
        guard var fields = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw WallpaperRemovalError(message: "\(id)/wallpaper.json is not a JSON object")
        }
        fields["name"] = name
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        library.scan()
    }

    func selectPack(_ id: String) {
        guard let pack = library.pack(withID: id) else { return }
        selectedPackID = id
        defaults.set(id, forKey: Self.selectedPackKey)
        scheduler.run(pack)
    }

    private func show(_ id: String) {
        guard let wallpaper = library.wallpaper(withID: id), supports(wallpaper) else { return }
        remember(id)
        if !isRequested(wallpaper) {
            switcher.switchTo(wallpaper)
        }
    }

    private func stopPack() {
        guard selectedPackID != nil else { return }
        selectedPackID = nil
        defaults.removeObject(forKey: Self.selectedPackKey)
        scheduler.run(nil)
    }

    private func libraryDidChange() {
        syncPack()

        if let id = selectedWallpaperID, let selected = library.wallpaper(withID: id), supports(selected) {
            if !isRequested(selected) {
                switcher.switchTo(selected)
            }
            return
        }
        if switcher.requested != nil {
            return
        }

        let candidates = library.wallpapers.filter(supports)
        let saved = candidates.first { $0.id == selectedWallpaperID }
        guard let target = saved ?? candidates.first else { return }
        remember(target.id)
        switcher.switchTo(target)
    }

    private func syncPack() {
        guard let id = selectedPackID else { return }
        let pack = library.pack(withID: id)
        if pack != scheduler.pack {
            scheduler.run(pack)
        }
    }

    private func isRequested(_ wallpaper: Wallpaper) -> Bool {
        switcher.requested?.hasSameContent(as: wallpaper) ?? false
    }

    private func remember(_ id: String) {
        selectedWallpaperID = id
        defaults.set(id, forKey: Self.selectedWallpaperKey)
    }
}

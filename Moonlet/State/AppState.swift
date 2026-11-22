import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let selectedWallpaperKey = "selectedWallpaperID"
    static let selectedPackKey = "selectedPackID"

    let library: Library
    private(set) var selectedWallpaperID: String?
    private(set) var selectedPackID: String?

    @ObservationIgnored let scheduler: PackScheduler
    @ObservationIgnored private let switcher: WallpaperSwitching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isSupported: @MainActor (WallpaperKind) -> Bool

    init(
        library: Library,
        switcher: WallpaperSwitching,
        defaults: UserDefaults = .standard,
        scheduler: PackScheduler = PackScheduler(),
        isSupported: @escaping @MainActor (WallpaperKind) -> Bool = RendererFactory.supports
    ) {
        self.library = library
        self.switcher = switcher
        self.defaults = defaults
        self.scheduler = scheduler
        self.isSupported = isSupported
        self.selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
        self.selectedPackID = defaults.string(forKey: Self.selectedPackKey)
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

    func selectPack(_ id: String) {
        guard let pack = library.pack(withID: id) else { return }
        selectedPackID = id
        defaults.set(id, forKey: Self.selectedPackKey)
        scheduler.run(pack)
    }

    private func show(_ id: String) {
        guard let wallpaper = library.wallpaper(withID: id), supports(wallpaper) else { return }
        remember(id)
        if switcher.requested != wallpaper {
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
            if switcher.requested != selected {
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

    private func remember(_ id: String) {
        selectedWallpaperID = id
        defaults.set(id, forKey: Self.selectedWallpaperKey)
    }
}

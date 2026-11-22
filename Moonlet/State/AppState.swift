import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let selectedWallpaperKey = "selectedWallpaperID"

    let library: Library
    private(set) var selectedWallpaperID: String?

    @ObservationIgnored private let switcher: WallpaperSwitching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isSupported: @MainActor (WallpaperKind) -> Bool

    init(
        library: Library,
        switcher: WallpaperSwitching,
        defaults: UserDefaults = .standard,
        isSupported: @escaping @MainActor (WallpaperKind) -> Bool = RendererFactory.supports
    ) {
        self.library = library
        self.switcher = switcher
        self.defaults = defaults
        self.isSupported = isSupported
        self.selectedWallpaperID = defaults.string(forKey: Self.selectedWallpaperKey)
    }

    var problems: [Problem] {
        (library.problems + switcher.problems).sorted { $0.location < $1.location }
    }

    func supports(_ wallpaper: Wallpaper) -> Bool {
        isSupported(wallpaper.kind)
    }

    func start(watching: Bool = true) {
        library.onChange = { [weak self] in
            self?.libraryDidChange()
        }
        library.scan()
        if watching {
            library.startWatching()
        }
    }

    func select(_ id: String) {
        guard let wallpaper = library.wallpaper(withID: id), supports(wallpaper) else { return }
        remember(id)
        switcher.switchTo(wallpaper)
    }

    private func libraryDidChange() {
        if let requested = switcher.requested {
            if let updated = library.wallpaper(withID: requested.id), updated != requested, supports(updated) {
                switcher.switchTo(updated)
            }
            return
        }

        let candidates = library.wallpapers.filter(supports)
        let saved = candidates.first { $0.id == selectedWallpaperID }
        guard let target = saved ?? candidates.first else { return }
        remember(target.id)
        switcher.switchTo(target)
    }

    private func remember(_ id: String) {
        selectedWallpaperID = id
        defaults.set(id, forKey: Self.selectedWallpaperKey)
    }
}

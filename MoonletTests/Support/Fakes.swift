import AppKit
@testable import Moonlet

@MainActor
final class FakeDisplayProvider: DisplayProvider {
    var displays: [DisplayInfo]

    init(_ displays: [DisplayInfo]) {
        self.displays = displays
    }
}

struct FakeLoadError: Error {}

@MainActor
final class FakeRenderer: WallpaperRenderer {
    var loadError: Error?
    var onProblem: ((String?) -> Void)?
    private(set) var attachedDisplayIDs: [CGDirectDisplayID] = []
    private(set) var detachedDisplayIDs: [CGDirectDisplayID] = []
    private(set) var views: [CGDirectDisplayID: NSView] = [:]
    private(set) var isPlaying = false
    private(set) var isTornDown = false

    init(loadError: Error? = nil) {
        self.loadError = loadError
    }

    func load() async throws {
        if let loadError {
            throw loadError
        }
    }

    func attach(to display: DisplayInfo) -> NSView {
        attachedDisplayIDs.append(display.id)
        let view = NSView(frame: NSRect(origin: .zero, size: display.frame.size))
        views[display.id] = view
        return view
    }

    func detach(from displayID: CGDirectDisplayID) {
        detachedDisplayIDs.append(displayID)
        views[displayID] = nil
    }

    func report(_ message: String?) {
        onProblem?(message)
    }

    func waitUntilReady() async {}
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func tearDown() { isTornDown = true }
}

@MainActor
final class FakeSwitcher: WallpaperSwitching {
    private(set) var requested: Wallpaper?
    var problems: [Problem] = []
    var failingIDs: Set<String> = []
    private(set) var switched: [Wallpaper] = []

    @discardableResult
    func switchTo(_ wallpaper: Wallpaper) -> Task<Void, Never> {
        switched.append(wallpaper)
        if !failingIDs.contains(wallpaper.id) {
            requested = wallpaper
        }
        return Task {}
    }
}

struct TestLibraryFolder {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "moonlet-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var wallpapersURL: URL {
        root.appending(path: "wallpapers", directoryHint: .isDirectory)
    }

    @discardableResult
    func addWallpaper(_ id: String, manifest: String?, files: [String] = []) throws -> URL {
        let folder = wallpapersURL.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: folder.appending(path: file))
        }
        if let manifest {
            try manifest.write(to: folder.appending(path: "wallpaper.json"), atomically: true, encoding: .utf8)
        }
        return folder
    }

    @discardableResult
    func addVideo(_ id: String, name: String) throws -> URL {
        try addWallpaper(
            id,
            manifest: #"{ "name": "\#(name)", "type": "video", "source": "clip.mp4" }"#,
            files: ["clip.mp4"]
        )
    }

    func removeWallpaper(_ id: String) throws {
        try FileManager.default.removeItem(at: wallpapersURL.appending(path: id))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

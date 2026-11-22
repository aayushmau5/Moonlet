import Foundation
import Testing
@testable import Moonlet

@MainActor
final class AppStateHarness {
    let folder: TestLibraryFolder
    let library: Library
    let switcher = FakeSwitcher()
    let defaults: UserDefaults
    private let suiteName = "moonlet-tests-\(UUID().uuidString)"

    init() throws {
        folder = try TestLibraryFolder()
        library = Library(rootURL: folder.root)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func makeState() -> AppState {
        AppState(library: library, switcher: switcher, defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        folder.remove()
    }
}

@MainActor
struct AppStateTests {
    @Test func restoresTheSavedWallpaper() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addVideo("two", name: "Two")
        harness.defaults.set("two", forKey: AppState.selectedWallpaperKey)
        let state = harness.makeState()

        state.start(watching: false)

        #expect(state.selectedWallpaperID == "two")
        #expect(harness.switcher.switched.map(\.id) == ["two"])
    }

    @Test func fallsBackToTheFirstSupportedWallpaper() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addWallpaper(
            "aurora",
            manifest: #"{ "name": "Aurora", "type": "metal", "source": "a.metal" }"#,
            files: ["a.metal"]
        )
        try harness.folder.addVideo("zebra", name: "Zebra")
        harness.defaults.set("deleted", forKey: AppState.selectedWallpaperKey)
        let state = harness.makeState()

        state.start(watching: false)

        #expect(state.selectedWallpaperID == "zebra")
        #expect(harness.defaults.string(forKey: AppState.selectedWallpaperKey) == "zebra")
    }

    @Test func doesNothingWithAnEmptyLibrary() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        let state = harness.makeState()

        state.start(watching: false)

        #expect(state.selectedWallpaperID == nil)
        #expect(harness.switcher.switched.isEmpty)
    }

    @Test func selectingSwitchesAndPersists() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addVideo("two", name: "Two")
        let state = harness.makeState()
        state.start(watching: false)

        state.select("two")

        #expect(state.selectedWallpaperID == "two")
        #expect(harness.switcher.switched.map(\.id) == ["one", "two"])
        #expect(harness.defaults.string(forKey: AppState.selectedWallpaperKey) == "two")
    }

    @Test func ignoresUnknownAndUnsupportedSelections() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addWallpaper(
            "aurora",
            manifest: #"{ "name": "Aurora", "type": "metal", "source": "a.metal" }"#,
            files: ["a.metal"]
        )
        let state = harness.makeState()
        state.start(watching: false)

        state.select("missing")
        state.select("aurora")

        #expect(state.selectedWallpaperID == "one")
        #expect(harness.switcher.switched.map(\.id) == ["one"])
    }

    @Test func reloadsTheCurrentWallpaperWhenItsManifestChanges() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        let state = harness.makeState()
        state.start(watching: false)

        try harness.folder.addVideo("one", name: "One Renamed")
        harness.library.scan()

        #expect(harness.switcher.switched.map(\.name) == ["One", "One Renamed"])
    }

    @Test func keepsPlayingWhenTheCurrentFolderIsDeleted() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addVideo("two", name: "Two")
        let state = harness.makeState()
        state.start(watching: false)

        try harness.folder.removeWallpaper("one")
        harness.library.scan()

        #expect(harness.switcher.switched.map(\.id) == ["one"])
    }

    @Test func ignoresUnrelatedLibraryChanges() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        let state = harness.makeState()
        state.start(watching: false)

        try harness.folder.addVideo("two", name: "Two")
        harness.library.scan()

        #expect(harness.switcher.switched.map(\.id) == ["one"])
    }

    @Test func picksAWallpaperOnceTheFirstOneIsAdded() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        let state = harness.makeState()
        state.start(watching: false)

        try harness.folder.addVideo("one", name: "One")
        harness.library.scan()

        #expect(state.selectedWallpaperID == "one")
        #expect(harness.switcher.switched.map(\.id) == ["one"])
    }

    @Test func combinesLibraryAndSwitcherProblems() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addWallpaper("broken", manifest: nil)
        harness.switcher.problems = [Problem(location: "wallpapers/one", message: "Could not load")]
        let state = harness.makeState()
        state.start(watching: false)

        #expect(state.problems.map(\.location) == ["wallpapers/broken", "wallpapers/one"])
    }
}

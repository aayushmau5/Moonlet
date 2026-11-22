import AppKit
import ServiceManagement
import Testing
@testable import Moonlet

@MainActor
struct LibraryRelocationTests {
    @Test func movingTheLibraryRescansAndRemembersThePath() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("old", name: "Old")
        let state = harness.makeState()
        state.start(watching: false)
        let other = try TestLibraryFolder()
        defer { other.remove() }
        try other.addVideo("fresh", name: "Fresh")

        state.moveLibrary(to: other.root)

        #expect(harness.library.rootURL == other.root)
        #expect(harness.library.wallpapers.map(\.id) == ["fresh"])
        #expect(harness.defaults.string(forKey: Library.rootPathKey) == other.root.path)
        #expect(state.selectedWallpaperID == "fresh")
        #expect(harness.switcher.switched.map(\.id) == ["old", "fresh"])
    }

    @Test func keepsTheSelectionWhenTheNewLibraryHasIt() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("shared", name: "Shared")
        let state = harness.makeState()
        state.start(watching: false)
        let other = try TestLibraryFolder()
        defer { other.remove() }
        try other.addVideo("another", name: "Another")
        try other.addVideo("shared", name: "Shared")

        state.moveLibrary(to: other.root)

        #expect(state.selectedWallpaperID == "shared")
    }

    @Test func savedPathIsUsedOnLaunch() {
        let defaults = UserDefaults(suiteName: "moonlet-root-\(UUID().uuidString)")!
        #expect(Library.savedRootURL(in: defaults) == Library.defaultRootURL)

        defaults.set("/tmp/elsewhere", forKey: Library.rootPathKey)
        #expect(Library.savedRootURL(in: defaults) == URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true))
    }
}

@MainActor
struct ThumbnailTests {
    func wallpaper(kind: WallpaperKind, source: URL) -> Wallpaper {
        Wallpaper(
            id: "thumb-\(kind.rawValue)",
            name: "Thumb",
            kind: kind,
            source: .file(source),
            soundtrack: nil,
            volume: 1,
            folder: source.deletingLastPathComponent()
        )
    }

    @Test func makesAThumbnailFromAVideo() async throws {
        let thumbnails = Thumbnails()

        let image = await thumbnails.image(for: wallpaper(kind: .video, source: try fixture("fixture-clip-silent.mp4")))

        #expect(image != nil)
    }

    @Test func rendersAThumbnailFromAShader() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let thumbnails = Thumbnails()

        let image = try #require(await thumbnails.image(for: wallpaper(kind: .metal, source: file.url)))

        #expect(image.size == Thumbnails.size)
    }

    @Test func webWallpapersHaveNoThumbnail() async {
        let thumbnails = Thumbnails()

        let image = await thumbnails.image(for: wallpaper(kind: .web, source: URL(fileURLWithPath: "/tmp/index.html")))

        #expect(image == nil)
    }
}

@MainActor
final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var failure: Error?

    func register() throws {
        if let failure { throw failure }
        status = .enabled
    }

    func unregister() throws {
        if let failure { throw failure }
        status = .notRegistered
    }
}

@MainActor
struct LoginItemTests {
    @Test func turnsOnAndOff() {
        let service = FakeLoginService()
        let item = LoginItem(service: service, bundlePath: "/Applications/Moonlet.app")

        item.setEnabled(true)
        #expect(item.isEnabled)
        #expect(item.statusText == "Moonlet starts when you log in")

        item.setEnabled(false)
        #expect(!item.isEnabled)
        #expect(item.statusText == "Off")
    }

    @Test func explainsWhenApprovalIsNeeded() {
        let service = FakeLoginService()
        service.status = .requiresApproval
        let item = LoginItem(service: service, bundlePath: "/Applications/Moonlet.app")

        #expect(item.statusText.contains("System Settings"))
    }

    @Test func reportsFailures() {
        let service = FakeLoginService()
        service.failure = FakeLoadError()
        let item = LoginItem(service: service, bundlePath: "/Applications/Moonlet.app")

        item.setEnabled(true)

        #expect(!item.isEnabled)
        #expect(item.errorText != nil)
    }

    @Test func warnsAboutDevelopmentBuilds() {
        let service = FakeLoginService()

        #expect(LoginItem(service: service, bundlePath: "/Applications/Moonlet.app").developmentWarning == nil)
        #expect(LoginItem(service: service, bundlePath: "/Users/me/moonlet/build/Moonlet.app").developmentWarning != nil)
    }
}

@MainActor
struct DeleteWallpaperTests {
    func harness() throws -> AppStateHarness {
        let harness = try AppStateHarness()
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addVideo("two", name: "Two")
        try harness.folder.addVideo("three", name: "Three")
        return harness
    }

    @Test func removesTheFolderAndKeepsTheCurrentWallpaper() throws {
        let harness = try harness()
        defer { harness.cleanUp() }
        let state = harness.makeState()
        state.start(watching: false)
        state.select("one")

        try state.moveToTrash("two")

        #expect(!FileManager.default.fileExists(atPath: harness.folder.wallpapersURL.appending(path: "two").path))
        #expect(harness.library.wallpapers.map(\.id) == ["one", "three"])
        #expect(state.selectedWallpaperID == "one")
    }

    @Test func showsAnotherWallpaperWhenTheCurrentOneGoes() throws {
        let harness = try harness()
        defer { harness.cleanUp() }
        let state = harness.makeState()
        state.start(watching: false)
        state.select("three")

        try state.moveToTrash("three")

        #expect(state.selectedWallpaperID == "one")
        #expect(harness.switcher.switched.last?.id == "one")
    }

    @Test func refusesAnUnknownWallpaper() throws {
        let harness = try harness()
        defer { harness.cleanUp() }
        let state = harness.makeState()
        state.start(watching: false)

        #expect(throws: (any Error).self) {
            try state.moveToTrash("missing")
        }
    }
}

@MainActor
struct RenameWallpaperTests {
    func manifest(_ harness: AppStateHarness, _ id: String) throws -> [String: Any] {
        let data = try Data(contentsOf: harness.folder.wallpapersURL.appending(path: "\(id)/wallpaper.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func changesTheNameAndKeepsEverythingElse() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addWallpaper(
            "rain",
            manifest: #"{ "name": "Rain", "type": "video", "source": "clip.mp4", "volume": 0.5 }"#,
            files: ["clip.mp4"]
        )
        let state = harness.makeState()
        state.start(watching: false)

        try state.rename("rain", to: "  Rain on Glass  ")

        let fields = try manifest(harness, "rain")
        #expect(fields["name"] as? String == "Rain on Glass")
        #expect(fields["type"] as? String == "video")
        #expect(fields["source"] as? String == "clip.mp4")
        #expect(fields["volume"] as? Double == 0.5)
        #expect(harness.library.wallpaper(withID: "rain")?.name == "Rain on Glass")
    }

    @Test func renamingTheCurrentWallpaperDoesNotReloadIt() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        let state = harness.makeState()
        state.start(watching: false)

        try state.rename("one", to: "First")

        #expect(harness.switcher.switched.map(\.name) == ["One"])
    }

    @Test func rejectsAnEmptyNameOrUnknownWallpaper() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        let state = harness.makeState()
        state.start(watching: false)

        #expect(throws: (any Error).self) { try state.rename("one", to: "   ") }
        #expect(throws: (any Error).self) { try state.rename("missing", to: "Name") }
        #expect(harness.library.wallpaper(withID: "one")?.name == "One")
    }

    @Test func aRealContentChangeStillReloads() throws {
        let harness = try AppStateHarness()
        defer { harness.cleanUp() }
        try harness.folder.addVideo("one", name: "One")
        let state = harness.makeState()
        state.start(watching: false)

        try harness.folder.addWallpaper(
            "one",
            manifest: #"{ "name": "One", "type": "video", "source": "clip.mp4", "volume": 0.3 }"#,
            files: ["clip.mp4"]
        )
        harness.library.scan()

        #expect(harness.switcher.switched.count == 2)
    }
}

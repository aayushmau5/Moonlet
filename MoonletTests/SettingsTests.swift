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

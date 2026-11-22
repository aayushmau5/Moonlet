import AppKit
import Testing
@testable import Moonlet

@MainActor
final class SwitcherHarness {
    let display = DisplayInfo(id: 1, frame: NSRect(x: 100_000, y: 100_000, width: 1710, height: 1112))
    let controller: DesktopWindowController
    private(set) var renderers: [String: FakeRenderer] = [:]
    var failingIDs: Set<String> = []
    var unsupportedIDs: Set<String> = []
    private(set) var madeIDs: [String] = []

    init() {
        controller = DesktopWindowController(displayProvider: FakeDisplayProvider([display]))
        controller.rebuild()
    }

    func makeSwitcher() -> WallpaperSwitcher {
        WallpaperSwitcher(desktop: controller, fadeDuration: 0) { [unowned self] wallpaper in
            self.madeIDs.append(wallpaper.id)
            guard !self.unsupportedIDs.contains(wallpaper.id) else { return nil }
            let renderer = FakeRenderer(loadError: self.failingIDs.contains(wallpaper.id) ? FakeLoadError() : nil)
            self.renderers[wallpaper.id] = renderer
            return renderer
        }
    }

    func wallpaper(_ id: String) -> Wallpaper {
        Wallpaper(
            id: id,
            name: id.capitalized,
            kind: .video,
            source: .file(URL(fileURLWithPath: "/tmp/\(id).mp4")),
            soundtrack: nil,
            volume: 1,
            folder: URL(fileURLWithPath: "/tmp/\(id)")
        )
    }
}

@MainActor
struct WallpaperSwitcherTests {
    @Test func showsTheWallpaperOnSuccess() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        let switcher = harness.makeSwitcher()

        await switcher.switchTo(harness.wallpaper("one")).value

        let renderer = harness.renderers["one"]
        #expect(switcher.current?.id == "one")
        #expect(renderer?.isPlaying == true)
        #expect(harness.controller.displayedView(on: 1) === renderer?.views[1])
    }

    @Test func keepsTheCurrentWallpaperWhenLoadingFails() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        harness.failingIDs = ["two"]
        let switcher = harness.makeSwitcher()
        await switcher.switchTo(harness.wallpaper("one")).value

        await switcher.switchTo(harness.wallpaper("two")).value

        #expect(switcher.current?.id == "one")
        #expect(switcher.requested?.id == "one")
        #expect(harness.controller.displayedView(on: 1) === harness.renderers["one"]?.views[1])
        #expect(harness.renderers["two"]?.isTornDown == true)
        #expect(switcher.problems.map(\.location) == ["wallpapers/two"])
    }

    @Test func reportsUnsupportedWallpapers() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        harness.unsupportedIDs = ["aurora"]
        let switcher = harness.makeSwitcher()

        await switcher.switchTo(harness.wallpaper("aurora")).value

        #expect(switcher.current == nil)
        #expect(switcher.problems.first?.message.contains("not supported yet") == true)
    }

    @Test func theLatestRequestWins() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        let switcher = harness.makeSwitcher()

        switcher.switchTo(harness.wallpaper("one"))
        await switcher.switchTo(harness.wallpaper("two")).value

        #expect(switcher.current?.id == "two")
        #expect(harness.madeIDs == ["two"])
    }

    @Test func rendererProblemsAppearAndClear() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        let switcher = harness.makeSwitcher()
        await switcher.switchTo(harness.wallpaper("one")).value
        let renderer = harness.renderers["one"]

        renderer?.report("line 3: oops")
        #expect(switcher.problems == [Problem(location: "wallpapers/one", message: "line 3: oops")])

        renderer?.report(nil)
        #expect(switcher.problems.isEmpty)
    }

    @Test func successClearsAnEarlierProblemForThatWallpaper() async {
        let harness = SwitcherHarness()
        defer { harness.controller.closeAll() }
        harness.failingIDs = ["one"]
        let switcher = harness.makeSwitcher()
        await switcher.switchTo(harness.wallpaper("one")).value

        harness.failingIDs = []
        await switcher.switchTo(harness.wallpaper("one")).value

        #expect(switcher.problems.isEmpty)
        #expect(switcher.current?.id == "one")
    }
}

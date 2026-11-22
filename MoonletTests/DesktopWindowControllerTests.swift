import AppKit
import Testing
@testable import Moonlet

@MainActor
struct DesktopWindowControllerTests {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 100_000, y: 100_000, width: 1710, height: 1112))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 102_000, y: 100_000, width: 2560, height: 1440))

    @Test func createsOneWindowPerDisplay() {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([laptop, external]))
        controller.rebuild()
        defer { controller.closeAll() }

        #expect(controller.windows.count == 2)
        #expect(controller.windows[1]?.frame == laptop.frame)
        #expect(controller.windows[2]?.frame == external.frame)
    }

    @Test func rebuildRemovesUnpluggedAndAddsNewDisplays() {
        let provider = FakeDisplayProvider([laptop])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }

        provider.displays = [external]
        controller.rebuild()

        #expect(Set(controller.windows.keys) == [2])
    }

    @Test func rebuildFollowsDisplayResize() {
        let provider = FakeDisplayProvider([laptop])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }
        let original = controller.windows[1]

        let resized = DisplayInfo(id: 1, frame: NSRect(x: 100_000, y: 100_000, width: 1512, height: 982))
        provider.displays = [resized]
        controller.rebuild()

        #expect(controller.windows[1] === original)
        #expect(controller.windows[1]?.frame == resized.frame)
    }

    @Test func crossfadeShowsRendererOnEveryWindowAndPlays() async {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([laptop, external]))
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()

        await controller.crossfade(to: renderer, duration: 0)

        #expect(Set(renderer.attachedDisplayIDs) == [1, 2])
        #expect(controller.displayedView(on: 1) === renderer.views[1])
        #expect(controller.displayedView(on: 2) === renderer.views[2])
        #expect(controller.windows[1]?.contentView?.subviews == [renderer.views[1]!])
        #expect(renderer.views[1]?.alphaValue == 1)
        #expect(renderer.isPlaying)
    }

    @Test func newDisplayGetsCurrentRenderer() async {
        let provider = FakeDisplayProvider([laptop])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()
        await controller.crossfade(to: renderer, duration: 0)

        provider.displays = [laptop, external]
        controller.rebuild()

        #expect(controller.displayedView(on: 2) === renderer.views[2])
        #expect(controller.windows[2]?.contentView?.subviews == [renderer.views[2]!])
    }

    @Test func unpluggedDisplayIsDetachedFromRenderer() async {
        let provider = FakeDisplayProvider([laptop, external])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()
        await controller.crossfade(to: renderer, duration: 0)

        provider.displays = [laptop]
        controller.rebuild()

        #expect(renderer.detachedDisplayIDs == [2])
        #expect(controller.displayedView(on: 2) == nil)
    }

    @Test func crossfadeTearsDownPreviousRendererAndRemovesItsViews() async {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([laptop]))
        controller.rebuild()
        defer { controller.closeAll() }
        let first = FakeRenderer()
        let second = FakeRenderer()

        await controller.crossfade(to: first, duration: 0)
        await controller.crossfade(to: second, duration: 0)

        #expect(first.isTornDown)
        #expect(!second.isTornDown)
        #expect(controller.windows[1]?.contentView?.subviews == [second.views[1]!])
    }
}

import AppKit
import Testing
@testable import Moonlet

@MainActor
final class FakeDisplayProvider: DisplayProvider {
    var displays: [DisplayInfo]

    init(_ displays: [DisplayInfo]) {
        self.displays = displays
    }
}

@MainActor
final class FakeRenderer: WallpaperRenderer {
    private(set) var attachedDisplayIDs: [CGDirectDisplayID] = []
    private(set) var detachedDisplayIDs: [CGDirectDisplayID] = []
    private(set) var views: [CGDirectDisplayID: NSView] = [:]
    private(set) var isPlaying = false
    private(set) var isTornDown = false

    func load() async throws {}

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

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func tearDown() { isTornDown = true }
}

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

    @Test func showAttachesRendererToEveryWindowAndPlays() {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([laptop, external]))
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()

        controller.show(renderer)

        #expect(Set(renderer.attachedDisplayIDs) == [1, 2])
        #expect(controller.windows[1]?.contentView === renderer.views[1])
        #expect(controller.windows[2]?.contentView === renderer.views[2])
        #expect(renderer.isPlaying)
    }

    @Test func newDisplayGetsCurrentRenderer() {
        let provider = FakeDisplayProvider([laptop])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()
        controller.show(renderer)

        provider.displays = [laptop, external]
        controller.rebuild()

        #expect(controller.windows[2]?.contentView === renderer.views[2])
    }

    @Test func unpluggedDisplayIsDetachedFromRenderer() {
        let provider = FakeDisplayProvider([laptop, external])
        let controller = DesktopWindowController(displayProvider: provider)
        controller.rebuild()
        defer { controller.closeAll() }
        let renderer = FakeRenderer()
        controller.show(renderer)

        provider.displays = [laptop]
        controller.rebuild()

        #expect(renderer.detachedDisplayIDs == [2])
    }

    @Test func showTearsDownPreviousRenderer() {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([laptop]))
        controller.rebuild()
        defer { controller.closeAll() }
        let first = FakeRenderer()
        let second = FakeRenderer()

        controller.show(first)
        controller.show(second)

        #expect(first.isTornDown)
        #expect(!second.isTornDown)
        #expect(controller.windows[1]?.contentView === second.views[1])
    }
}

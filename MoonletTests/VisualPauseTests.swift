import AppKit
import MetalKit
import Testing
import WebKit
@testable import Moonlet

struct CoverageTests {
    let visible = CGRect(x: 0, y: 25, width: 1710, height: 1020)
    let ownPID: pid_t = 100

    func window(_ bounds: CGRect, layer: Int = 0, alpha: Double = 1, pid: pid_t = 200) -> WindowInfo {
        WindowInfo(bounds: bounds, layer: layer, alpha: alpha, ownerPID: pid)
    }

    func covered(_ windows: [WindowInfo]) -> Bool {
        Coverage.isCovered(visibleFrame: visible, windows: windows, ownPID: ownPID)
    }

    @Test func aFullscreenWindowCovers() {
        #expect(covered([window(CGRect(x: 0, y: 0, width: 1710, height: 1112))]))
    }

    @Test func aWindowFillingTheUsableAreaCovers() {
        #expect(covered([window(CGRect(x: 0, y: 25, width: 1710, height: 1000))]))
    }

    @Test func aLargePartialWindowDoesNotCover() {
        #expect(!covered([window(CGRect(x: 100, y: 100, width: 1400, height: 800))]))
    }

    @Test func ignoresOwnInvisibleAndNonNormalWindows() {
        let full = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        #expect(!covered([window(full, pid: ownPID)]))
        #expect(!covered([window(full, alpha: 0)]))
        #expect(!covered([window(full, layer: 25)]))
    }

    @Test func convertsCocoaFramesToWindowServerCoordinates() {
        let primaryHeight: CGFloat = 1112
        let primary = Coverage.windowServerRect(fromCocoa: CGRect(x: 0, y: 0, width: 1710, height: 1112), primaryScreenHeight: primaryHeight)
        let above = Coverage.windowServerRect(fromCocoa: CGRect(x: 0, y: 1112, width: 2560, height: 1440), primaryScreenHeight: primaryHeight)
        let menuBarless = Coverage.windowServerRect(fromCocoa: CGRect(x: 0, y: 0, width: 1710, height: 1080), primaryScreenHeight: primaryHeight)

        #expect(primary == CGRect(x: 0, y: 0, width: 1710, height: 1112))
        #expect(above == CGRect(x: 0, y: -1440, width: 2560, height: 1440))
        #expect(menuBarless == CGRect(x: 0, y: 32, width: 1710, height: 1080))
    }
}

@MainActor
final class VisibilityHarness {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 0, y: 0, width: 1710, height: 1112))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 1710, y: 0, width: 2560, height: 1440))
    var windows: [WindowInfo] = []
    var occluded: Set<CGDirectDisplayID> = []
    let start = ContinuousClock.now
    private(set) var changes: [Set<CGDirectDisplayID>] = []
    lazy var monitor: VisibilityMonitor = {
        let monitor = VisibilityMonitor(
            displayProvider: FakeDisplayProvider([laptop, external]),
            readWindows: { [unowned self] in self.windows },
            isOccluded: { [unowned self] in self.occluded.contains($0) }
        )
        monitor.onChange = { [unowned self] in self.changes.append($0) }
        return monitor
    }()

    func cover(_ display: DisplayInfo) {
        windows = [WindowInfo(bounds: display.frame, layer: 0, alpha: 1, ownerPID: 999)]
    }

    func check(at seconds: Double) {
        monitor.check(at: start + .milliseconds(Int(seconds * 1000)))
    }
}

@MainActor
struct VisibilityMonitorTests {
    @Test func coveredAfterOneSecond() {
        let harness = VisibilityHarness()
        harness.cover(harness.laptop)

        harness.check(at: 0)
        harness.check(at: 0.9)
        #expect(harness.monitor.covered.isEmpty)

        harness.check(at: 1)
        #expect(harness.monitor.covered == [1])
        #expect(harness.changes == [[1]])
    }

    @Test func uncoveredImmediately() {
        let harness = VisibilityHarness()
        harness.cover(harness.laptop)
        harness.check(at: 0)
        harness.check(at: 1)

        harness.windows = []
        harness.check(at: 1.1)

        #expect(harness.monitor.covered.isEmpty)
        #expect(harness.changes == [[1], []])
    }

    @Test func ignoresBriefOcclusionFlips() {
        let harness = VisibilityHarness()

        harness.occluded = [1, 2]
        harness.check(at: 0)
        harness.occluded = []
        harness.check(at: 0.2)
        harness.check(at: 2)

        #expect(harness.changes.isEmpty)
    }

    @Test func occlusionAloneCoversAfterTheDelay() {
        let harness = VisibilityHarness()
        harness.occluded = [2]

        harness.check(at: 0)
        harness.check(at: 1)

        #expect(harness.monitor.covered == [2])
    }
}

@MainActor
struct RendererPauseTests {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 800, y: 0, width: 800, height: 600))

    @Test func videoPausesOnlyWhenEveryScreenIsPaused() {
        let renderer = VideoRenderer(url: URL(fileURLWithPath: "/nonexistent/clip.mp4"))
        _ = renderer.attach(to: laptop)
        _ = renderer.attach(to: external)
        renderer.play()

        renderer.setPausedDisplays([1])
        #expect(renderer.isRunning)

        renderer.setPausedDisplays([1, 2])
        #expect(!renderer.isRunning)

        renderer.setPausedDisplays([])
        #expect(renderer.isRunning)
        renderer.tearDown()
    }

    @Test func metalPausesPerScreenAndFreezesTimeWhenAllArePaused() async throws {
        let file = try ShaderFile(Shaders.solid(0, 0, 1))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()
        let first = try #require(renderer.attach(to: laptop) as? MTKView)
        let second = try #require(renderer.attach(to: external) as? MTKView)
        renderer.play()

        renderer.setPausedDisplays([1])
        #expect(first.isPaused && !second.isPaused)
        #expect(renderer.isClockRunning)

        renderer.setPausedDisplays([1, 2])
        #expect(first.isPaused && second.isPaused)
        #expect(!renderer.isClockRunning)

        renderer.setPausedDisplays([])
        #expect(!first.isPaused && !second.isPaused)
        #expect(renderer.isClockRunning)
        renderer.tearDown()
    }

    @Test func webSuspendsPerScreen() async throws {
        let folder = try WebPageFolder(title: "Pause")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        let first = try #require(renderer.attach(to: laptop) as? WKWebView)
        let second = try #require(renderer.attach(to: external) as? WKWebView)
        renderer.play()

        renderer.setPausedDisplays([2])

        #expect(renderer.pausedDisplayIDs == [2])
        #expect(!first.isHidden)
        #expect(second.isHidden)

        renderer.setPausedDisplays([])
        #expect(!second.isHidden)
        renderer.tearDown()
    }

    @Test func controllerAppliesPausedScreensToANewWallpaper() async {
        let controller = DesktopWindowController(displayProvider: FakeDisplayProvider([
            DisplayInfo(id: 1, frame: NSRect(x: 100_000, y: 100_000, width: 800, height: 600)),
            DisplayInfo(id: 2, frame: NSRect(x: 101_000, y: 100_000, width: 800, height: 600)),
        ]))
        controller.rebuild()
        defer { controller.closeAll() }
        controller.setPausedDisplays([2])
        let renderer = FakeRenderer()

        await controller.crossfade(to: renderer, duration: 0)

        #expect(renderer.pausedDisplays == [2])

        controller.setPausedDisplays([])
        #expect(renderer.pausedDisplays == [])
    }
}

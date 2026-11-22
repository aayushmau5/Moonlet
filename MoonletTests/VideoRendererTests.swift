import AVFoundation
import AppKit
import Testing
@testable import Moonlet

@MainActor
struct VideoRendererTests {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 0, y: 0, width: 1710, height: 1112))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 1710, y: 0, width: 2560, height: 1440))
    let anyURL = URL(fileURLWithPath: "/nonexistent/video.mp4")

    @Test func playerIsMutedAndAllowsDisplaySleep() {
        let renderer = VideoRenderer(url: anyURL)
        #expect(renderer.player.isMuted)
        #expect(!renderer.player.preventsDisplaySleepDuringVideoPlayback)
    }

    @Test func everyDisplaySharesOnePlayer() throws {
        let renderer = VideoRenderer(url: anyURL)

        let first = try #require(renderer.attach(to: laptop) as? PlayerLayerView)
        let second = try #require(renderer.attach(to: external) as? PlayerLayerView)

        #expect(first.playerLayer.player === renderer.player)
        #expect(second.playerLayer.player === renderer.player)
        #expect(first.playerLayer.videoGravity == .resizeAspectFill)
    }

    @Test func detachReleasesTheDisplaysView() {
        let renderer = VideoRenderer(url: anyURL)
        _ = renderer.attach(to: laptop)
        _ = renderer.attach(to: external)

        renderer.detach(from: 2)

        #expect(Set(renderer.attachedDisplayIDs) == [1])
    }

    @Test func loadFailsForAFileThatIsNotVideo() async throws {
        let textFile = FileManager.default.temporaryDirectory
            .appending(path: "moonlet-not-video-\(UUID().uuidString).mp4")
        try "not a video".write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }

        let renderer = VideoRenderer(url: textFile)

        await #expect(throws: (any Error).self) {
            try await renderer.load()
        }
    }

    @Test func tearDownStopsPlaybackAndReleasesViews() {
        let renderer = VideoRenderer(url: anyURL)
        _ = renderer.attach(to: laptop)

        renderer.tearDown()

        #expect(renderer.attachedDisplayIDs.isEmpty)
        #expect(renderer.player.items().isEmpty)
    }
}

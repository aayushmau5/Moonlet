import AVFoundation
import AppKit

enum VideoRendererError: Error, Equatable {
    case notPlayable(URL)
}

@MainActor
final class VideoRenderer: WallpaperRenderer {
    let player = AVQueuePlayer()
    var onProblem: ((String?) -> Void)?
    private let url: URL
    private var looper: AVPlayerLooper?
    private var views: [CGDirectDisplayID: PlayerLayerView] = [:]
    private var wantsToRun = false
    private var pausedDisplays: Set<CGDirectDisplayID> = []
    private(set) var isRunning = false

    var attachedDisplayIDs: [CGDirectDisplayID] {
        Array(views.keys)
    }

    init(url: URL) {
        self.url = url
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
    }

    func load() async throws {
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw VideoRendererError.notPlayable(url)
        }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
    }

    func attach(to display: DisplayInfo) -> NSView {
        let view = PlayerLayerView(player: player)
        view.frame = NSRect(origin: .zero, size: display.frame.size)
        views[display.id] = view
        return view
    }

    func detach(from displayID: CGDirectDisplayID) {
        views[displayID]?.playerLayer.player = nil
        views[displayID] = nil
        applyRunState()
    }

    func waitUntilReady() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while let layer = views.values.first?.playerLayer,
              !layer.isReadyForDisplay,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    func play() {
        wantsToRun = true
        applyRunState()
    }

    func pause() {
        wantsToRun = false
        applyRunState()
    }

    func setPausedDisplays(_ displays: Set<CGDirectDisplayID>) {
        pausedDisplays = displays
        applyRunState()
    }

    private func applyRunState() {
        let everyScreenPaused = !views.isEmpty && Set(views.keys).isSubset(of: pausedDisplays)
        let shouldRun = wantsToRun && !everyScreenPaused
        guard shouldRun != isRunning else { return }
        isRunning = shouldRun
        if shouldRun {
            player.play()
        } else {
            player.pause()
        }
    }

    func still(on displayID: CGDirectDisplayID) async -> CGImage? {
        guard views[displayID] != nil, let asset = player.currentItem?.asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: player.currentTime()).image
    }

    func tearDown() {
        wantsToRun = false
        isRunning = false
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        for id in views.keys {
            detach(from: id)
        }
    }
}

final class PlayerLayerView: NSView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }
}

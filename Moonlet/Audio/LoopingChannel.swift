import AVFoundation

@MainActor
final class LoopingChannel: AudioChannel {
    var onNowPlaying: ((String) -> Void)?
    var onProblem: ((String) -> Void)?
    private(set) var hasVideoTracks = false

    private let url: URL
    private let isVideoAudio: Bool
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var loopCount: Int {
        looper?.loopCount ?? 0
    }
    init(url: URL, isVideoAudio: Bool) {
        self.url = url
        self.isVideoAudio = isVideoAudio
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func load() async throws {
        let asset = isVideoAudio ? try await Self.audioOnlyAsset(from: url) : try await Self.playableAsset(at: url)
        hasVideoTracks = !(try await asset.loadTracks(withMediaType: .video)).isEmpty
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    private static func playableAsset(at url: URL) async throws -> AVAsset {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw AudioError(message: "\(url.lastPathComponent) cannot be played")
        }
        return asset
    }

    private static func audioOnlyAsset(from url: URL) async throws -> AVAsset {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioError(message: "\(url.lastPathComponent) has no audio track")
        }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioError(message: "Could not read the audio of \(url.lastPathComponent)")
        }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        return composition
    }
}

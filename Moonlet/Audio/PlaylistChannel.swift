import AVFoundation

@MainActor
final class PlaylistChannel: AudioChannel, PlaylistControlling {
    var onNowPlaying: ((String) -> Void)?
    var onProblem: ((String) -> Void)?

    private let playlist: Playlist
    private let player = AVPlayer()
    private let startSeconds: Double
    private var index: Int
    private var isShuffled: Bool
    private var isPlaying = false
    private var consecutiveFailures = 0
    private var observers: [NSObjectProtocol] = []

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var position: PlaylistPosition {
        let seconds = player.currentTime().seconds
        return PlaylistPosition(trackIndex: index, seconds: seconds.isFinite ? seconds : 0)
    }

    init(playlist: Playlist, start: PlaylistPosition?, shuffled: Bool) {
        self.playlist = playlist
        let startIndex = start?.trackIndex ?? 0
        self.index = playlist.tracks.indices.contains(startIndex) ? startIndex : 0
        self.startSeconds = start?.seconds ?? 0
        self.isShuffled = shuffled
        player.allowsExternalPlayback = false
    }

    static func nextIndex(after current: Int, count: Int, shuffled: Bool) -> Int {
        guard count > 1 else { return 0 }
        guard shuffled else { return (current + 1) % count }
        let pick = Int.random(in: 0..<(count - 1))
        return pick >= current ? pick + 1 : pick
    }

    func load() async throws {
        guard !playlist.tracks.isEmpty else {
            throw AudioError(message: "The playlist has no tracks")
        }
        observeItemEnds()
        if await prepareTrack(at: index, seconds: startSeconds) {
            return
        }
        guard await advance(afterFailure: true) else {
            throw AudioError(message: "No track in this playlist could be played")
        }
    }

    func play() {
        isPlaying = true
        player.play()
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func stop() {
        pause()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    func setShuffled(_ shuffled: Bool) {
        isShuffled = shuffled
    }

    private func prepareTrack(at trackIndex: Int, seconds: Double) async -> Bool {
        index = trackIndex
        let asset = AVURLAsset(url: playlist.tracks[trackIndex])
        guard (try? await asset.load(.isPlayable)) == true else { return false }

        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        if seconds > 0 {
            await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        onNowPlaying?(playlist.tracks[trackIndex].deletingPathExtension().lastPathComponent)
        return true
    }

    @discardableResult
    private func advance(afterFailure failed: Bool) async -> Bool {
        consecutiveFailures = failed ? consecutiveFailures + 1 : 0
        guard consecutiveFailures < playlist.tracks.count else {
            onProblem?("No track in this playlist could be played")
            stop()
            return false
        }

        let next = Self.nextIndex(after: index, count: playlist.tracks.count, shuffled: isShuffled)
        guard await prepareTrack(at: next, seconds: 0) else {
            return await advance(afterFailure: true)
        }
        if isPlaying {
            player.play()
        }
        return true
    }

    private func observeItemEnds() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let events: [(Notification.Name, Bool)] = [
            (AVPlayerItem.didPlayToEndTimeNotification, false),
            (AVPlayerItem.failedToPlayToEndTimeNotification, true),
        ]
        for (name, failed) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let item = notification.object as? AVPlayerItem
                MainActor.assumeIsolated {
                    self?.itemEnded(item, failed: failed)
                }
            }
            observers.append(observer)
        }
    }

    private func itemEnded(_ item: AVPlayerItem?, failed: Bool) {
        guard let item, item === player.currentItem else { return }
        Task {
            await advance(afterFailure: failed)
        }
    }
}

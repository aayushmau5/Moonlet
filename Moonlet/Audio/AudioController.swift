import Foundation
import Observation
import os

@MainActor
private final class ActiveChannel {
    var source: AudioSource
    let channel: AudioChannel
    var gain: Float = 0
    var title: String?
    var fadeTask: Task<Void, Never>?

    init(source: AudioSource, channel: AudioChannel) {
        self.source = source
        self.channel = channel
    }
}

@MainActor
@Observable
final class AudioController {
    struct Fades: Sendable {
        var crossfade: Duration
        var pauseOut: Duration
        var resumeIn: Duration

        static let standard = Fades(crossfade: .milliseconds(1500), pauseOut: .seconds(1), resumeIn: .seconds(2))
        static let instant = Fades(crossfade: .zero, pauseOut: .zero, resumeIn: .zero)
    }

    typealias ChannelMaker = @MainActor (AudioSource, PlaylistPosition?, Bool) -> AudioChannel?

    static let selectionKey = "musicSelection"
    static let volumeKey = "musicVolume"
    static let shuffleKey = "musicShuffle"
    static let pausedKey = "musicUserPaused"
    static let defaultVolume = 0.6

    private(set) var selection: MusicSelection = .none
    private(set) var volume: Double
    private(set) var isShuffled: Bool
    private(set) var isUserPaused: Bool
    private(set) var nowPlaying: NowPlaying?
    private(set) var problems: [Problem] = []
    private(set) var isStarted = false

    @ObservationIgnored let library: Library
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fades: Fades
    @ObservationIgnored private let makeChannel: ChannelMaker
    @ObservationIgnored private var wallpaper: Wallpaper?
    @ObservationIgnored private var active: ActiveChannel?
    @ObservationIgnored private var playlistPositions: [String: PlaylistPosition] = [:]
    @ObservationIgnored private var failedIdentity: String?
    @ObservationIgnored private var lastTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "audio")

    init(
        library: Library,
        defaults: UserDefaults = .standard,
        fades: Fades = .standard,
        makeChannel: @escaping ChannelMaker = AudioChannelFactory.make
    ) {
        self.library = library
        self.defaults = defaults
        self.fades = fades
        self.makeChannel = makeChannel
        self.volume = defaults.object(forKey: Self.volumeKey) as? Double ?? Self.defaultVolume
        self.isShuffled = defaults.bool(forKey: Self.shuffleKey)
        self.isUserPaused = defaults.bool(forKey: Self.pausedKey)
    }

    @discardableResult
    func start(wallpaper: Wallpaper?) -> Task<Void, Never> {
        self.wallpaper = wallpaper
        isStarted = true
        if let saved = MusicSelection(storageValue: defaults.string(forKey: Self.selectionKey)) {
            selection = saved
        } else if let first = library.playlists.first {
            selection = .playlist(first.id)
            defaults.set(selection.storageValue, forKey: Self.selectionKey)
        }
        return enqueue { await $0.transition() }
    }

    @discardableResult
    func wallpaperShown(_ wallpaper: Wallpaper) -> Task<Void, Never> {
        guard isStarted else { return start(wallpaper: wallpaper) }
        self.wallpaper = wallpaper
        return enqueue { await $0.transition() }
    }

    @discardableResult
    func libraryChanged() -> Task<Void, Never> {
        guard isStarted else { return Task {} }
        return enqueue { await $0.transition() }
    }

    @discardableResult
    func select(_ newSelection: MusicSelection) -> Task<Void, Never> {
        selection = newSelection
        failedIdentity = nil
        defaults.set(newSelection.storageValue, forKey: Self.selectionKey)
        return enqueue { await $0.transition() }
    }

    @discardableResult
    func togglePause() -> Task<Void, Never> {
        isUserPaused.toggle()
        defaults.set(isUserPaused, forKey: Self.pausedKey)
        let paused = isUserPaused
        return enqueue { await $0.applyPause(paused) }
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(newVolume, 0), 1)
        defaults.set(volume, forKey: Self.volumeKey)
        if let active {
            apply(active)
        }
    }

    func setShuffled(_ shuffled: Bool) {
        isShuffled = shuffled
        defaults.set(shuffled, forKey: Self.shuffleKey)
        (active?.channel as? PlaylistControlling)?.setShuffled(shuffled)
    }

    private func enqueue(_ work: @escaping @MainActor (AudioController) async -> Void) -> Task<Void, Never> {
        let previous = lastTask
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
        lastTask = task
        return task
    }

    private func transition() async {
        let source = AudioSource.effective(
            wallpaper: wallpaper,
            selection: selection,
            playlists: library.playlists,
            streams: library.streams
        )

        if let active, active.source.identity == source?.identity, let source {
            active.source = source
            apply(active)
            return
        }

        if let old = active {
            retire(old)
            active = nil
        }
        nowPlaying = nil
        guard let source else {
            logger.info("Music: nothing to play")
            return
        }
        guard source.identity != failedIdentity else {
            logger.info("Music: \(source.identity, privacy: .public) failed earlier; waiting to be picked again")
            return
        }

        let start = playlistStart(for: source)
        guard let channel = makeChannel(source, start, isShuffled) else {
            report("Could not create a player", for: source)
            return
        }
        let candidate = ActiveChannel(source: source, channel: channel)
        channel.onNowPlaying = { [weak self, weak candidate] title in
            guard let self, let candidate else { return }
            candidate.title = title
            if self.active === candidate {
                self.nowPlaying = NowPlaying(title: title, detail: candidate.source.defaultNowPlaying.detail)
            }
        }
        channel.onProblem = { [weak self, weak candidate] message in
            guard let self, let candidate else { return }
            self.channelFailed(candidate, message: message)
        }

        do {
            try await channel.load()
        } catch {
            channel.stop()
            report("Could not play: \(error.localizedDescription)", for: source)
            return
        }

        clearProblem(for: source)
        active = candidate
        apply(candidate)
        let fallback = source.defaultNowPlaying
        nowPlaying = NowPlaying(title: candidate.title ?? fallback.title, detail: fallback.detail)
        logger.info("Music: now \(source.identity, privacy: .public)\(self.isUserPaused ? " (paused)" : "", privacy: .public)")

        if !isUserPaused {
            channel.play()
            fade(candidate, to: 1, over: fades.crossfade)
        }
    }

    private func channelFailed(_ failed: ActiveChannel, message: String) {
        report(message, for: failed.source)
        guard active === failed else { return }
        failed.fadeTask?.cancel()
        failed.channel.stop()
        active = nil
        nowPlaying = nil
        failedIdentity = failed.source.identity
    }

    private func applyPause(_ paused: Bool) async {
        guard let active else { return }
        active.fadeTask?.cancel()
        if paused {
            await ramp(active, to: 0, over: fades.pauseOut)
            if isUserPaused {
                active.channel.pause()
                logger.info("Music: paused")
            }
        } else {
            active.channel.play()
            fade(active, to: 1, over: fades.resumeIn)
            logger.info("Music: resumed")
        }
    }

    private func retire(_ old: ActiveChannel) {
        if case .playlist(let playlist) = old.source, let controlling = old.channel as? PlaylistControlling {
            playlistPositions[playlist.id] = controlling.position
        }
        old.fadeTask?.cancel()
        guard fades.crossfade > .zero else {
            old.channel.stop()
            return
        }
        old.fadeTask = Task { [weak self] in
            await self?.ramp(old, to: 0, over: self?.fades.crossfade ?? .zero)
            old.channel.stop()
        }
    }

    private func playlistStart(for source: AudioSource) -> PlaylistPosition? {
        guard case .playlist(let playlist) = source else { return nil }
        return playlistPositions[playlist.id]
    }

    private func fade(_ active: ActiveChannel, to target: Float, over duration: Duration) {
        active.fadeTask?.cancel()
        guard duration > .zero else {
            active.gain = target
            apply(active)
            return
        }
        active.fadeTask = Task { [weak self] in
            await self?.ramp(active, to: target, over: duration)
        }
    }

    private func ramp(_ active: ActiveChannel, to target: Float, over duration: Duration) async {
        let start = active.gain
        guard duration > .zero else {
            active.gain = target
            apply(active)
            return
        }
        let steps = max(Int(duration / .milliseconds(25)), 1)
        for step in 1...steps {
            try? await Task.sleep(for: duration / steps)
            if Task.isCancelled { return }
            let progress = Float(Fader.eased(Double(step) / Double(steps)))
            active.gain = start + (target - start) * progress
            apply(active)
        }
    }

    private func apply(_ active: ActiveChannel) {
        active.channel.volume = Float(volume * active.source.volume) * active.gain
    }

    private func report(_ message: String, for source: AudioSource) {
        logger.error("Music: \(source.identity, privacy: .public): \(message, privacy: .public)")
        problems.removeAll { $0.location == source.location }
        problems.append(Problem(location: source.location, message: message))
    }

    private func clearProblem(for source: AudioSource) {
        problems.removeAll { $0.location == source.location }
    }
}

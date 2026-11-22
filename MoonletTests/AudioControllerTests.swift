import Foundation
import Testing
@testable import Moonlet

@MainActor
final class FakeChannel: AudioChannel, PlaylistControlling {
    let source: AudioSource
    var volume: Float = 0
    var onNowPlaying: ((String) -> Void)?
    var onProblem: ((String) -> Void)?
    var loadError: Error?
    var position: PlaylistPosition
    private(set) var isShuffled: Bool
    private(set) var isPlaying = false
    private(set) var isStopped = false

    init(source: AudioSource, start: PlaylistPosition?, shuffled: Bool) {
        self.source = source
        self.position = start ?? PlaylistPosition(trackIndex: 0, seconds: 0)
        self.isShuffled = shuffled
    }

    func load() async throws {
        if let loadError {
            throw loadError
        }
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() {
        isPlaying = false
        isStopped = true
    }

    func setShuffled(_ shuffled: Bool) {
        isShuffled = shuffled
    }

    func fail(_ message: String) {
        stop()
        onProblem?(message)
    }
}

@MainActor
final class AudioHarness {
    let folder: TestLibraryFolder
    let library: Library
    let defaults: UserDefaults
    var failingSources: Set<String> = []
    private(set) var channels: [FakeChannel] = []
    private let suiteName = "moonlet-audio-tests-\(UUID().uuidString)"

    init() throws {
        folder = try TestLibraryFolder()
        library = Library(rootURL: folder.root)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func makeController() -> AudioController {
        AudioController(library: library, defaults: defaults, fades: .instant) { [unowned self] source, start, shuffled in
            let channel = FakeChannel(source: source, start: start, shuffled: shuffled)
            if self.failingSources.contains(source.identity) {
                channel.loadError = FakeLoadError()
            }
            self.channels.append(channel)
            return channel
        }
    }

    var live: [FakeChannel] {
        channels.filter { !$0.isStopped }
    }

    func video(_ id: String, soundtrack: Soundtrack? = nil, volume: Double = 1) -> Wallpaper {
        Wallpaper(
            id: id,
            name: id.capitalized,
            kind: .video,
            source: .file(URL(fileURLWithPath: "/tmp/\(id)/clip.mp4")),
            soundtrack: soundtrack,
            volume: volume,
            folder: URL(fileURLWithPath: "/tmp/\(id)")
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        folder.remove()
    }
}

@MainActor
struct AudioControllerTests {
    @Test func playsTheSavedPlaylist() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        try harness.folder.addPlaylist("sleep", files: ["b.mp3"])
        harness.library.scan()
        harness.defaults.set("playlist:sleep", forKey: AudioController.selectionKey)
        let audio = harness.makeController()

        await audio.start(wallpaper: nil).value

        #expect(harness.live.count == 1)
        #expect(harness.live.first?.source.identity == "playlist:sleep")
        #expect(harness.live.first?.isPlaying == true)
        #expect(harness.live.first?.volume == Float(AudioController.defaultVolume))
    }

    @Test func defaultsToTheFirstPlaylistAndRemembersIt() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()

        await audio.start(wallpaper: nil).value

        #expect(audio.selection == .playlist("focus"))
        #expect(harness.defaults.string(forKey: AudioController.selectionKey) == "playlist:focus")
    }

    @Test func respectsAChoiceOfNoMusic() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        harness.defaults.set("none", forKey: AudioController.selectionKey)
        let audio = harness.makeController()

        await audio.start(wallpaper: nil).value

        #expect(harness.channels.isEmpty)
        #expect(audio.nowPlaying == nil)
    }

    @Test func soundtrackTakesOverAndThePlaylistResumesAfterwards() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3", "b.mp3", "c.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: harness.video("plain")).value
        let playlist = try #require(harness.live.first)
        playlist.position = PlaylistPosition(trackIndex: 2, seconds: 30)

        let rainURL = URL(fileURLWithPath: "/tmp/rain/rain.m4a")
        await audio.wallpaperShown(harness.video("rain", soundtrack: .file(rainURL), volume: 0.5)).value

        #expect(playlist.isStopped)
        let soundtrack = try #require(harness.live.first)
        #expect(soundtrack.source.identity == "soundtrack:\(rainURL.path)")
        #expect(soundtrack.isPlaying)
        #expect(soundtrack.volume == Float(AudioController.defaultVolume * 0.5))

        await audio.wallpaperShown(harness.video("plain")).value

        let resumed = try #require(harness.live.first)
        #expect(resumed.source.identity == "playlist:focus")
        #expect(resumed.position == PlaylistPosition(trackIndex: 2, seconds: 30))
    }

    @Test func videoSoundtrackUsesTheVideoFile() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        let audio = harness.makeController()
        let beach = harness.video("beach", soundtrack: .videoTrack)

        await audio.start(wallpaper: beach).value

        guard case .soundtrack(let soundtrack) = harness.live.first?.source else {
            Issue.record("Expected a soundtrack source")
            return
        }
        #expect(soundtrack.url == URL(fileURLWithPath: "/tmp/beach/clip.mp4"))
        #expect(soundtrack.isVideoAudio)
    }

    @Test func doesNotRestartTheSameSource() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: harness.video("one")).value

        await audio.wallpaperShown(harness.video("two")).value

        #expect(harness.channels.count == 1)
    }

    @Test func pauseIsRememberedAcrossLaunches() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        await audio.togglePause().value

        #expect(audio.isUserPaused)
        #expect(harness.live.first?.isPlaying == false)

        let relaunched = harness.makeController()
        await relaunched.start(wallpaper: nil).value

        #expect(relaunched.isUserPaused)
        #expect(harness.live.last?.isPlaying == false)
    }

    @Test func playResumesAfterPause() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value
        await audio.togglePause().value

        await audio.togglePause().value

        #expect(!audio.isUserPaused)
        #expect(harness.live.first?.isPlaying == true)
        #expect(harness.channels.count == 1)
    }

    @Test func volumeScalesWithTheSoundtrackVolume() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        let audio = harness.makeController()
        let rain = harness.video("rain", soundtrack: .file(URL(fileURLWithPath: "/tmp/rain/rain.m4a")), volume: 0.5)
        await audio.start(wallpaper: rain).value

        audio.setVolume(0.8)

        #expect(harness.live.first?.volume == Float(0.8 * 0.5))
        #expect(harness.defaults.double(forKey: AudioController.volumeKey) == 0.8)
    }

    @Test func selectingNoneStopsTheMusic() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        await audio.select(.none).value

        #expect(harness.live.isEmpty)
        #expect(audio.nowPlaying == nil)
        #expect(harness.defaults.string(forKey: AudioController.selectionKey) == "none")
    }

    @Test func shuffleReachesThePlaylistAndPersists() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        audio.setShuffled(true)

        #expect(harness.live.first?.isShuffled == true)
        #expect(harness.defaults.bool(forKey: AudioController.shuffleKey))
    }

    @Test func aSourceThatFailsToLoadBecomesAProblem() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        harness.failingSources = ["playlist:focus"]
        let audio = harness.makeController()

        await audio.start(wallpaper: nil).value

        #expect(audio.problems.map(\.location) == ["music/focus"])
        #expect(audio.nowPlaying == nil)
    }

    @Test func deletingThePlayingPlaylistStopsTheMusic() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        try harness.folder.removePlaylist("focus")
        harness.library.scan()
        await audio.libraryChanged().value

        #expect(harness.live.isEmpty)
    }

    @Test func reportsWhatIsPlaying() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        harness.live.first?.onNowPlaying?("Morning Drone")

        #expect(audio.nowPlaying == NowPlaying(title: "Morning Drone", detail: "focus"))
    }
}

struct EffectiveSourceTests {
    let playlists = [Playlist(id: "focus", tracks: [URL(fileURLWithPath: "/tmp/a.mp3")])]

    func wallpaper(soundtrack: Soundtrack?) -> Wallpaper {
        Wallpaper(
            id: "w",
            name: "W",
            kind: .video,
            source: .file(URL(fileURLWithPath: "/tmp/w/clip.mp4")),
            soundtrack: soundtrack,
            volume: 0.4,
            folder: URL(fileURLWithPath: "/tmp/w")
        )
    }

    @Test func soundtrackWinsOverTheSelection() {
        let source = AudioSource.effective(
            wallpaper: wallpaper(soundtrack: .file(URL(fileURLWithPath: "/tmp/w/rain.m4a"))),
            selection: .playlist("focus"),
            playlists: playlists
        )
        #expect(source?.identity == "soundtrack:/tmp/w/rain.m4a")
        #expect(source?.volume == 0.4)
    }

    @Test func selectionPlaysWithoutASoundtrack() {
        let source = AudioSource.effective(wallpaper: wallpaper(soundtrack: nil), selection: .playlist("focus"), playlists: playlists)
        #expect(source == .playlist(playlists[0]))
        #expect(source?.volume == 1)
    }

    @Test func nothingPlaysForNoneOrAMissingPlaylist() {
        #expect(AudioSource.effective(wallpaper: nil, selection: .none, playlists: playlists) == nil)
        #expect(AudioSource.effective(wallpaper: nil, selection: .playlist("gone"), playlists: playlists) == nil)
    }
}

struct FaderTests {
    @Test func easesBetweenEnds() {
        #expect(Fader.eased(0) == 0)
        #expect(Fader.eased(0.5) == 0.5)
        #expect(Fader.eased(1) == 1)
        #expect(Fader.eased(0.25) < 0.25)
        #expect(Fader.eased(-1) == 0)
        #expect(Fader.eased(2) == 1)
    }
}

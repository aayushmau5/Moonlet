import Foundation
import Testing
@testable import Moonlet

extension TestLibraryFolder {
    var streamsURL: URL {
        root.appending(path: "streams.json")
    }

    func writeStreams(_ json: String) throws {
        try json.write(to: streamsURL, atomically: true, encoding: .utf8)
    }
}

struct StreamsFileTests {
    @Test func readsStreamsInFileOrder() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.writeStreams("""
        [
          { "name": "Drone Zone", "url": "https://ice1.example.com/drone" },
          { "name": "Groove", "url": "http://radio.example.com/groove.mp3" }
        ]
        """)

        let result = StreamsFile.load(from: folder.streamsURL)

        #expect(result.streams.map(\.name) == ["Drone Zone", "Groove"])
        #expect(result.streams.first?.url == URL(string: "https://ice1.example.com/drone"))
        #expect(result.problems.isEmpty)
    }

    @Test func aMissingFileMeansNoStreams() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }

        let result = StreamsFile.load(from: folder.streamsURL)

        #expect(result.streams.isEmpty)
        #expect(result.problems.isEmpty)
    }

    @Test func reportsAFileThatIsNotAList() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.writeStreams(#"{ "name": "Solo" }"#)

        let result = StreamsFile.load(from: folder.streamsURL)

        #expect(result.streams.isEmpty)
        #expect(result.problems.count == 1)
        #expect(result.problems.first?.location == "streams.json")
        #expect(result.problems.first?.message.contains("not valid") == true)
    }

    @Test func reportsBadEntriesAndKeepsGoodOnes() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.writeStreams("""
        [
          { "name": "Good", "url": "https://example.com/good" },
          { "url": "https://example.com/nameless" },
          { "name": "No URL" },
          { "name": "Local", "url": "file:///tmp/song.mp3" },
          { "name": "Good", "url": "https://example.com/again" }
        ]
        """)

        let result = StreamsFile.load(from: folder.streamsURL)

        #expect(result.streams.map(\.name) == ["Good"])
        #expect(result.problems.map(\.message) == [
            #"entry 2: missing "name""#,
            #"No URL: missing "url""#,
            "Local: the URL must start with http:// or https://",
            "Good: the name is used twice",
        ])
    }

    @Test @MainActor func libraryScanIncludesStreams() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.writeStreams(#"[{ "name": "Drone", "url": "https://example.com/drone" }]"#)
        let library = Library(rootURL: folder.root)

        library.scan()

        #expect(library.streams.map(\.name) == ["Drone"])
    }
}

struct RetryPolicyTests {
    let policy = RetryPolicy.standard

    @Test func waitsLongerAfterEachFailureThenGivesUp() {
        #expect(policy.delay(afterFailures: 1) == .seconds(2))
        #expect(policy.delay(afterFailures: 2) == .seconds(5))
        #expect(policy.delay(afterFailures: 3) == .seconds(15))
        #expect(policy.delay(afterFailures: 4) == nil)
    }

    @Test func resetsAfterThirtySecondsOfCleanPlay() {
        #expect(!policy.shouldReset(afterHealthyFor: nil))
        #expect(!policy.shouldReset(afterHealthyFor: .seconds(29)))
        #expect(policy.shouldReset(afterHealthyFor: .seconds(30)))
    }
}

struct StreamSelectionTests {
    @Test func streamSelectionRoundTripsThroughStorage() {
        #expect(MusicSelection.stream("Drone Zone").storageValue == "stream:Drone Zone")
        #expect(MusicSelection(storageValue: "stream:Drone Zone") == .stream("Drone Zone"))
    }

    @Test func effectiveSourcePicksTheSelectedStream() {
        let stream = RadioStream(name: "Drone", url: URL(string: "https://example.com/drone")!)

        let source = AudioSource.effective(wallpaper: nil, selection: .stream("Drone"), playlists: [], streams: [stream])

        #expect(source == .stream(stream))
        #expect(source?.identity == "stream:https://example.com/drone")
        #expect(source?.location == "streams.json")
        #expect(source?.defaultNowPlaying == NowPlaying(title: "Drone", detail: "Internet radio"))
        #expect(AudioSource.effective(wallpaper: nil, selection: .stream("Gone"), playlists: [], streams: [stream]) == nil)
    }
}

@MainActor
struct StreamControllerTests {
    let streamsJSON = #"[{ "name": "Drone", "url": "https://example.com/drone" }]"#

    @Test func playsTheSelectedStream() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.writeStreams(streamsJSON)
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value

        await audio.select(.stream("Drone")).value

        #expect(harness.live.map(\.source.identity) == ["stream:https://example.com/drone"])
        #expect(harness.live.first?.isPlaying == true)
        #expect(audio.nowPlaying == NowPlaying(title: "Drone", detail: "Internet radio"))
    }

    @Test func aSoundtrackTakesOverAndTheStreamRejoinsFresh() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.writeStreams(streamsJSON)
        harness.library.scan()
        harness.defaults.set("stream:Drone", forKey: AudioController.selectionKey)
        let audio = harness.makeController()
        await audio.start(wallpaper: harness.video("plain")).value

        let rain = harness.video("rain", soundtrack: .file(URL(fileURLWithPath: "/tmp/rain/rain.m4a")))
        await audio.wallpaperShown(rain).value
        await audio.wallpaperShown(harness.video("plain")).value

        #expect(harness.channels.map(\.source.identity) == [
            "stream:https://example.com/drone",
            "soundtrack:/tmp/rain/rain.m4a",
            "stream:https://example.com/drone",
        ])
        #expect(harness.live.count == 1)
    }

    @Test func aFailedStreamStopsAndWaitsToBePickedAgain() async throws {
        let harness = try AudioHarness()
        defer { harness.cleanUp() }
        try harness.folder.writeStreams(streamsJSON)
        harness.library.scan()
        harness.defaults.set("stream:Drone", forKey: AudioController.selectionKey)
        let audio = harness.makeController()
        await audio.start(wallpaper: harness.video("one")).value

        harness.live.first?.fail("Stream stopped: offline")

        #expect(harness.live.isEmpty)
        #expect(audio.nowPlaying == nil)
        #expect(audio.problems == [Problem(location: "streams.json", message: "Stream stopped: offline")])

        await audio.wallpaperShown(harness.video("two")).value
        #expect(harness.channels.count == 1)

        await audio.select(.stream("Drone")).value
        #expect(harness.channels.count == 2)
        #expect(harness.live.count == 1)
    }
}

@MainActor
struct StreamChannelTests {
    let fastPolicy = RetryPolicy(
        delays: [.milliseconds(10), .milliseconds(10), .milliseconds(10)],
        resetAfter: .seconds(30)
    )

    @Test func playsAReachableStream() async throws {
        let stream = RadioStream(name: "Local", url: try fixture("fixture-tone-a.m4a"))
        let channel = StreamChannel(stream: stream, policy: fastPolicy, stallTimeout: .seconds(5))
        var titles: [String] = []
        channel.onNowPlaying = { titles.append($0) }
        channel.volume = 0

        try await channel.load()
        channel.play()
        await waitFor({ channel.hasStartedPlaying }, timeout: .seconds(4))
        channel.stop()

        #expect(channel.hasStartedPlaying)
        #expect(titles.first == "Local")
    }

    @Test func retriesThreeTimesThenReportsAProblem() async throws {
        let stream = RadioStream(name: "Broken", url: URL(fileURLWithPath: "/nonexistent/moonlet-stream.mp3"))
        let channel = StreamChannel(stream: stream, policy: fastPolicy, stallTimeout: .seconds(5))
        var problems: [String] = []
        channel.onProblem = { problems.append($0) }
        channel.volume = 0

        try await channel.load()
        channel.play()
        await waitFor({ !problems.isEmpty }, timeout: .seconds(5))

        #expect(channel.attemptCount == 4)
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("Stream stopped:") == true)
    }
}

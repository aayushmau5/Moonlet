import AVFoundation
import Foundation
import Testing
@testable import Moonlet

final class FixtureLocator {}

func fixture(_ name: String) throws -> URL {
    let bundle = Bundle(for: FixtureLocator.self)
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    return try #require(bundle.url(forResource: base, withExtension: ext), "Missing fixture \(name)")
}

@MainActor
struct PlaylistChannelTests {
    func playlist() throws -> Playlist {
        Playlist(id: "fixtures", tracks: [try fixture("fixture-tone-a.m4a"), try fixture("fixture-tone-b.m4a")])
    }

    @Test func advancesToTheNextTrack() async throws {
        let channel = PlaylistChannel(playlist: try playlist(), start: nil, shuffled: false)
        var titles: [String] = []
        channel.onNowPlaying = { titles.append($0) }
        channel.volume = 0
        try await channel.load()

        channel.play()
        await waitFor({ titles.count >= 2 }, timeout: .seconds(4))
        channel.stop()

        #expect(Array(titles.prefix(2)) == ["fixture-tone-a", "fixture-tone-b"])
    }

    @Test func wrapsAroundAfterTheLastTrack() async throws {
        let channel = PlaylistChannel(
            playlist: try playlist(),
            start: PlaylistPosition(trackIndex: 1, seconds: 0),
            shuffled: false
        )
        var titles: [String] = []
        channel.onNowPlaying = { titles.append($0) }
        channel.volume = 0
        try await channel.load()

        channel.play()
        await waitFor({ titles.count >= 2 }, timeout: .seconds(4))
        channel.stop()

        #expect(Array(titles.prefix(2)) == ["fixture-tone-b", "fixture-tone-a"])
    }

    @Test func startsAtTheSavedPosition() async throws {
        let channel = PlaylistChannel(
            playlist: try playlist(),
            start: PlaylistPosition(trackIndex: 1, seconds: 0.2),
            shuffled: false
        )
        channel.volume = 0
        try await channel.load()

        #expect(channel.position.trackIndex == 1)
        #expect(abs(channel.position.seconds - 0.2) < 0.05)
        channel.stop()
    }

    @Test func shuffleNeverRepeatsTheCurrentTrack() {
        for _ in 0..<50 {
            #expect(PlaylistChannel.nextIndex(after: 1, count: 3, shuffled: true) != 1)
        }
        #expect(PlaylistChannel.nextIndex(after: 0, count: 1, shuffled: true) == 0)
        #expect(PlaylistChannel.nextIndex(after: 2, count: 3, shuffled: false) == 0)
    }
}

@MainActor
struct LoopingChannelTests {
    @Test func loopsAnAudioFile() async throws {
        let channel = LoopingChannel(url: try fixture("fixture-tone-a.m4a"), isVideoAudio: false)
        channel.volume = 0
        try await channel.load()

        channel.play()
        await waitFor({ channel.loopCount >= 2 }, timeout: .seconds(4))
        let loops = channel.loopCount
        channel.stop()

        #expect(loops >= 2)
    }

    @Test func playsTheAudioOfAVideo() async throws {
        let channel = LoopingChannel(url: try fixture("fixture-clip-with-audio.mp4"), isVideoAudio: true)
        channel.volume = 0

        try await channel.load()

        #expect(channel.hasVideoTracks == false)
        channel.stop()
    }

    @Test func failsForAVideoWithoutAudio() async throws {
        let channel = LoopingChannel(url: try fixture("fixture-clip-silent.mp4"), isVideoAudio: true)

        await #expect(throws: (any Error).self) {
            try await channel.load()
        }
    }
}

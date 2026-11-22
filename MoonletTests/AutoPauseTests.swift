import Foundation
import Testing
@testable import Moonlet

struct AppNamingTests {
    let ignored: Set<String> = ["systemsoundserverd", "com.vorssaint.utils"]
    let ownPID: pid_t = 100

    func process(_ bundleID: String, app: String? = nil, process: String? = nil, pid: pid_t = 200) -> AudioProcess {
        AudioProcess(pid: pid, bundleID: bundleID, appName: app, processName: process)
    }

    func name(_ process: AudioProcess) -> String {
        AppNaming.displayName(for: process) { bundleID in
            bundleID == "com.google.Chrome" ? "Google Chrome" : nil
        }
    }

    @Test func stripsTheWebKitHelperSuffix() {
        #expect(name(process("com.apple.WebKit.GPU", app: "Safari Graphics and Media")) == "Safari")
    }

    @Test func mapsHelperBundlesToTheirApp() {
        #expect(name(process("com.google.Chrome.helper", app: nil)) == "Google Chrome")
        #expect(name(process("com.google.Chrome.helper", app: "Google Chrome Helper (Aperitif)")) == "Google Chrome")
    }

    @Test func fallsBackThroughAppProcessAndBundleNames() {
        #expect(name(process("com.spotify.client", app: "Spotify")) == "Spotify")
        #expect(name(process("", app: nil, process: "afplay")) == "afplay")
        #expect(name(process("org.example.tool")) == "org.example.tool")
        #expect(name(process("")) == "Another app")
    }

    @Test func ignoresItselfItsHelpersAndTheIgnoreList() {
        func isIgnored(_ process: AudioProcess) -> Bool {
            AppNaming.isIgnored(process, ownPID: ownPID, ignoredBundleIDs: ignored)
        }
        #expect(isIgnored(process("dev.moonlet.Moonlet", app: "Moonlet", pid: ownPID)))
        #expect(isIgnored(process("com.apple.WebKit.GPU", app: "Moonlet Graphics and Media")))
        #expect(isIgnored(process("systemsoundserverd")))
        #expect(isIgnored(process("com.vorssaint.utils", app: "Vorssaint")))
        #expect(!isIgnored(process("com.apple.WebKit.GPU", app: "Safari Graphics and Media")))
        #expect(!isIgnored(process("com.spotify.client", app: "Spotify")))
    }
}

struct DelayedSignalTests {
    let start = ContinuousClock.now

    func outputs(_ steps: [(raw: Bool, at: Double)]) -> [Bool] {
        var signal = DelayedSignal(onDelay: .seconds(3), offDelay: .seconds(5))
        return steps.map { signal.update(raw: $0.raw, at: start + .milliseconds(Int($0.at * 1000))) }
    }

    @Test func turnsOnOnlyAfterTheOnDelay() {
        #expect(outputs([(true, 0), (true, 2.9), (true, 3)]) == [false, false, true])
    }

    @Test func turnsOffOnlyAfterTheOffDelay() {
        let result = outputs([(true, 0), (true, 3), (false, 4), (false, 8.9), (false, 9)])
        #expect(result == [false, true, true, true, false])
    }

    @Test func ignoresShortBlips() {
        let result = outputs([(true, 0), (false, 2), (true, 3), (true, 5.9), (true, 6)])
        #expect(result == [false, false, false, false, true])
    }

    @Test func aShortQuietGapDoesNotResume() {
        let result = outputs([(true, 0), (true, 3), (false, 4), (true, 6), (false, 7), (false, 11.9), (false, 12)])
        #expect(result == [false, true, true, true, true, true, false])
    }
}

@MainActor
struct PauseReasonTests {
    func playingController() async throws -> (AudioHarness, AudioController) {
        let harness = try AudioHarness()
        try harness.folder.addPlaylist("focus", files: ["a.mp3"])
        harness.library.scan()
        let audio = harness.makeController()
        await audio.start(wallpaper: nil).value
        return (harness, audio)
    }

    @Test func otherAudioPausesAndResumes() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }

        await audio.setOtherAudio("Safari").value
        #expect(harness.live.first?.isPlaying == false)
        #expect(audio.isPaused)
        #expect(audio.pauseDescription == "Paused: Safari is playing")

        await audio.setOtherAudio(nil).value
        #expect(harness.live.first?.isPlaying == true)
        #expect(!audio.isPaused)
        #expect(audio.pauseDescription == nil)
    }

    @Test func systemPausePausesAndResumes() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }

        await audio.setSystemPause("screen locked").value
        #expect(harness.live.first?.isPlaying == false)
        #expect(audio.pauseDescription == "Paused: screen locked")

        await audio.setSystemPause(nil).value
        #expect(harness.live.first?.isPlaying == true)
    }

    @Test func resumesOnlyWhenEveryReasonClears() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }
        await audio.setOtherAudio("Spotify").value
        await audio.setSystemPause("screen locked").value

        await audio.setOtherAudio(nil).value
        #expect(harness.live.first?.isPlaying == false)

        await audio.setSystemPause(nil).value
        #expect(harness.live.first?.isPlaying == true)
    }

    @Test func playOverridesOtherAudioUntilItStops() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }
        await audio.setOtherAudio("Safari").value

        await audio.togglePause().value
        #expect(harness.live.first?.isPlaying == true)
        #expect(!audio.isPaused)

        await audio.setOtherAudio("Spotify").value
        #expect(harness.live.first?.isPlaying == true)

        await audio.setOtherAudio(nil).value
        await audio.setOtherAudio("Spotify").value
        #expect(harness.live.first?.isPlaying == false)
    }

    @Test func automaticPausesAreNotRemembered() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }
        await audio.setOtherAudio("Safari").value

        let relaunched = harness.makeController()
        await relaunched.start(wallpaper: nil).value

        #expect(!relaunched.isPaused)
        #expect(harness.live.last?.isPlaying == true)
    }

    @Test func aNewSourceStaysQuietWhileAutoPaused() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }
        await audio.setOtherAudio("Safari").value

        let rain = harness.video("rain", soundtrack: .file(URL(fileURLWithPath: "/tmp/rain/rain.m4a")))
        await audio.wallpaperShown(rain).value

        #expect(harness.live.first?.source.identity == "soundtrack:/tmp/rain/rain.m4a")
        #expect(harness.live.first?.isPlaying == false)

        await audio.setOtherAudio(nil).value
        #expect(harness.live.first?.isPlaying == true)
    }

    @Test func userPauseStillShowsPlainPaused() async throws {
        let (harness, audio) = try await playingController()
        defer { harness.cleanUp() }

        await audio.togglePause().value

        #expect(audio.pauseDescription == "Paused")
    }
}

@MainActor
struct PlaybackMonitorTests {
    @Test func seesAnotherProcessPlaying() async throws {
        let monitor = PlaybackMonitor(ignoredBundleIDs: [], pollInterval: .milliseconds(100))
        monitor.start()
        defer { monitor.stop() }

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0", try fixture("fixture-tone-long.m4a").path]
        try player.run()
        defer { player.terminate() }

        await waitFor({ monitor.playingApps.contains("afplay") }, timeout: .seconds(3))

        #expect(monitor.playingApps.contains("afplay"))
    }
}

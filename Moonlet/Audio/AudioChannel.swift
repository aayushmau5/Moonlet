import Foundation

struct AudioError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
protocol AudioChannel: AnyObject {
    var volume: Float { get set }
    var onNowPlaying: ((String) -> Void)? { get set }
    var onProblem: ((String) -> Void)? { get set }

    func load() async throws
    func play()
    func pause()
    func stop()
}

@MainActor
protocol PlaylistControlling: AnyObject {
    var position: PlaylistPosition { get }
    func setShuffled(_ shuffled: Bool)
}

@MainActor
enum AudioChannelFactory {
    static func make(source: AudioSource, start: PlaylistPosition?, shuffled: Bool) -> AudioChannel? {
        switch source {
        case .soundtrack(let soundtrack):
            return LoopingChannel(url: soundtrack.url, isVideoAudio: soundtrack.isVideoAudio)
        case .playlist(let playlist):
            return PlaylistChannel(playlist: playlist, start: start, shuffled: shuffled)
        }
    }
}

enum Fader {
    static func eased(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

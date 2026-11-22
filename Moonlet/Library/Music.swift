import Foundation

struct Playlist: Identifiable, Equatable, Sendable {
    let id: String
    let tracks: [URL]

    var name: String { id }
    var location: String { "music/\(id)" }
}

struct RadioStream: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL

    var id: String { name }
}

enum MusicSelection: Hashable, Sendable {
    case none
    case playlist(String)
    case stream(String)

    init?(storageValue: String?) {
        guard let storageValue else { return nil }
        if storageValue == "none" {
            self = .none
        } else if storageValue.hasPrefix("playlist:") {
            self = .playlist(String(storageValue.dropFirst("playlist:".count)))
        } else if storageValue.hasPrefix("stream:") {
            self = .stream(String(storageValue.dropFirst("stream:".count)))
        } else {
            return nil
        }
    }

    var storageValue: String {
        switch self {
        case .none: "none"
        case .playlist(let id): "playlist:\(id)"
        case .stream(let name): "stream:\(name)"
        }
    }
}

struct PlaylistPosition: Equatable, Sendable {
    let trackIndex: Int
    let seconds: Double
}

struct NowPlaying: Equatable, Sendable {
    let title: String
    let detail: String
}

struct SoundtrackSource: Equatable, Sendable {
    let wallpaperID: String
    let wallpaperName: String
    let url: URL
    let isVideoAudio: Bool
    let volume: Double
}

enum AudioSource: Equatable, Sendable {
    case soundtrack(SoundtrackSource)
    case playlist(Playlist)
    case stream(RadioStream)

    var identity: String {
        switch self {
        case .soundtrack(let soundtrack): "soundtrack:\(soundtrack.url.path)"
        case .playlist(let playlist): "playlist:\(playlist.id)"
        case .stream(let stream): "stream:\(stream.url.absoluteString)"
        }
    }

    var volume: Double {
        switch self {
        case .soundtrack(let soundtrack): soundtrack.volume
        case .playlist, .stream: 1
        }
    }

    var location: String {
        switch self {
        case .soundtrack(let soundtrack): "wallpapers/\(soundtrack.wallpaperID)"
        case .playlist(let playlist): playlist.location
        case .stream: StreamsFile.fileName
        }
    }

    var defaultNowPlaying: NowPlaying {
        switch self {
        case .soundtrack(let soundtrack): NowPlaying(title: soundtrack.wallpaperName, detail: "Wallpaper soundtrack")
        case .playlist(let playlist): NowPlaying(title: playlist.name, detail: playlist.name)
        case .stream(let stream): NowPlaying(title: stream.name, detail: "Internet radio")
        }
    }

    static func effective(
        wallpaper: Wallpaper?,
        selection: MusicSelection,
        playlists: [Playlist],
        streams: [RadioStream] = []
    ) -> AudioSource? {
        if let wallpaper, let soundtrack = soundtrackSource(for: wallpaper) {
            return .soundtrack(soundtrack)
        }
        switch selection {
        case .none:
            return nil
        case .playlist(let id):
            return playlists.first { $0.id == id }.map(AudioSource.playlist)
        case .stream(let name):
            return streams.first { $0.name == name }.map(AudioSource.stream)
        }
    }

    private static func soundtrackSource(for wallpaper: Wallpaper) -> SoundtrackSource? {
        switch (wallpaper.soundtrack, wallpaper.source) {
        case (.file(let url), _):
            return SoundtrackSource(wallpaperID: wallpaper.id, wallpaperName: wallpaper.name, url: url, isVideoAudio: false, volume: wallpaper.volume)
        case (.videoTrack, .file(let videoURL)):
            return SoundtrackSource(wallpaperID: wallpaper.id, wallpaperName: wallpaper.name, url: videoURL, isVideoAudio: true, volume: wallpaper.volume)
        default:
            return nil
        }
    }
}

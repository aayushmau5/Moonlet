import Foundation

enum WallpaperKind: String, CaseIterable, Sendable {
    case video
    case metal
    case web
}

enum WallpaperSource: Equatable, Sendable {
    case file(URL)
    case remote(URL)
}

enum Soundtrack: Equatable, Sendable {
    case file(URL)
    case videoTrack
}

struct Wallpaper: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: WallpaperKind
    let source: WallpaperSource
    let soundtrack: Soundtrack?
    let volume: Double
    let folder: URL
    var renderScale: Double = 1
    var image: URL?

    var location: String {
        "wallpapers/\(id)"
    }

    func hasSameContent(as other: Wallpaper) -> Bool {
        id == other.id
            && kind == other.kind
            && source == other.source
            && soundtrack == other.soundtrack
            && volume == other.volume
            && renderScale == other.renderScale
            && image == other.image
    }
}

struct Problem: Identifiable, Equatable, Sendable {
    let location: String
    let message: String

    var id: String {
        "\(location): \(message)"
    }
}

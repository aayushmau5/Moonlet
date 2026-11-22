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

    var location: String {
        "wallpapers/\(id)"
    }
}

struct Problem: Identifiable, Equatable, Sendable {
    let location: String
    let message: String

    var id: String {
        "\(location): \(message)"
    }
}

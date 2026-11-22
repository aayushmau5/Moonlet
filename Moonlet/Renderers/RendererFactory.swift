import Foundation

@MainActor
enum RendererFactory {
    static func supports(_ kind: WallpaperKind) -> Bool {
        kind == .video
    }

    static func makeRenderer(for wallpaper: Wallpaper) -> WallpaperRenderer? {
        switch (wallpaper.kind, wallpaper.source) {
        case (.video, .file(let url)):
            return VideoRenderer(url: url)
        default:
            return nil
        }
    }
}

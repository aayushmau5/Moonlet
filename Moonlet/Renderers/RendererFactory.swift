import Foundation
import Metal

@MainActor
enum RendererFactory {
    static func supports(_ kind: WallpaperKind) -> Bool {
        kind == .video || kind == .metal
    }

    static func makeRenderer(for wallpaper: Wallpaper) -> WallpaperRenderer? {
        switch (wallpaper.kind, wallpaper.source) {
        case (.video, .file(let url)):
            return VideoRenderer(url: url)
        case (.metal, .file(let url)):
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            return MetalRenderer(sourceURL: url, device: device)
        default:
            return nil
        }
    }
}

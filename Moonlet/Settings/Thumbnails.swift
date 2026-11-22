import AVFoundation
import AppKit
import Metal

@MainActor
final class Thumbnails {
    static let size = NSSize(width: 480, height: 300)

    private var cache: [String: NSImage] = [:]

    func image(for wallpaper: Wallpaper) async -> NSImage? {
        guard case .file(let source) = wallpaper.source else { return nil }
        let imageDate = wallpaper.image.flatMap(Self.modificationDate(of:))?.timeIntervalSince1970 ?? 0
        let key = "\(wallpaper.id)|\(source.path)|\(Self.modificationDate(of: source)?.timeIntervalSince1970 ?? 0)|\(imageDate)"
        if let cached = cache[key] {
            return cached
        }

        let image: NSImage?
        switch wallpaper.kind {
        case .video:
            image = await videoFrame(from: source)
        case .metal:
            image = await shaderFrame(from: source, image: wallpaper.image)
        case .web:
            image = nil
        }
        if let image {
            cache[key] = image
        }
        return image
    }

    private func videoFrame(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.size
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let time = CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)
        guard let frame = try? await generator.image(at: time).image else { return nil }
        return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }

    private func shaderFrame(from url: URL, image: URL?) async -> NSImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = MetalRenderer(sourceURL: url, device: device, imageURL: image, watchesSource: false)
        guard (try? await renderer.load()) != nil,
              let frame = try? renderer.snapshot(width: Int(Self.size.width), height: Int(Self.size.height), time: 12) else {
            return nil
        }
        return NSImage(cgImage: frame, size: Self.size)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

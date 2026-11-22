import AppKit
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import Moonlet

private let snapshotDirectory = ProcessInfo.processInfo.environment["MOONLET_SNAPSHOT_DIR"]

@MainActor
@Suite(.enabled(if: snapshotDirectory != nil, "Set MOONLET_SNAPSHOT_DIR, or run make snapshots"))
struct WallpaperReviewSnapshots {
    let size = NSSize(width: 1710, height: 1112)

    @Test func renderLibraryShaders() async throws {
        let output = try outputDirectory()
        let device = try #require(MTLCreateSystemDefaultDevice())

        for wallpaper in scannedLibrary() where wallpaper.kind == .metal {
            guard case .file(let url) = wallpaper.source else { continue }
            let renderer = MetalRenderer(sourceURL: url, device: device, watchesSource: false)
            try await renderer.load()
            for time: Float in [0, 15, 30] {
                let image = try renderer.snapshot(width: Int(size.width), height: Int(size.height), time: time)
                try save(image, to: output.appending(path: "\(wallpaper.id)-t\(Int(time)).png"))
            }
        }
    }

    @Test func renderLibraryWebPages() async throws {
        let output = try outputDirectory()
        let display = DisplayInfo(id: 1, frame: NSRect(origin: .zero, size: size))

        for wallpaper in scannedLibrary() where wallpaper.kind == .web {
            let renderer = WebRenderer(source: wallpaper.source, folder: wallpaper.folder, watchesSource: false)
            try await renderer.load()
            let view = try #require(renderer.attach(to: display) as? WKWebView)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            await renderer.waitUntilReady()
            try await Task.sleep(for: .seconds(1))

            let image = try await view.takeSnapshot(configuration: nil)
            let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            try save(cgImage, to: output.appending(path: "\(wallpaper.id).png"))
            renderer.tearDown()
            window.close()
        }
    }

    private func outputDirectory() throws -> URL {
        let output = URL(fileURLWithPath: try #require(snapshotDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func scannedLibrary() -> [Wallpaper] {
        let library = Library()
        library.scan()
        return library.wallpapers
    }

    private func save(_ image: CGImage, to file: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

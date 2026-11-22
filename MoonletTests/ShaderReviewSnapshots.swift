import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import Moonlet

private let snapshotDirectory = ProcessInfo.processInfo.environment["MOONLET_SNAPSHOT_DIR"]

@MainActor
@Suite(.enabled(if: snapshotDirectory != nil, "Set MOONLET_SNAPSHOT_DIR, or run make snapshots"))
struct ShaderReviewSnapshots {
    @Test func renderLibraryShaders() async throws {
        let output = URL(fileURLWithPath: try #require(snapshotDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = Library()
        library.scan()

        for wallpaper in library.wallpapers where wallpaper.kind == .metal {
            guard case .file(let url) = wallpaper.source else { continue }
            let renderer = MetalRenderer(sourceURL: url, device: device, watchesSource: false)
            try await renderer.load()
            for time: Float in [0, 15, 30] {
                let image = try renderer.snapshot(width: 1710, height: 1112, time: time)
                let file = output.appending(path: "\(wallpaper.id)-t\(Int(time)).png")
                let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
            }
        }
    }
}

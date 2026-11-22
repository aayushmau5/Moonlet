import AppKit
import Metal
import MetalKit
import Testing
@testable import Moonlet

@MainActor
final class ShaderFile {
    let folder: URL
    let url: URL

    init(_ source: String) throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "moonlet-shader-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "test.metal")
        try write(source)
    }

    func write(_ source: String) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    func makeRenderer() throws -> MetalRenderer {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return MetalRenderer(sourceURL: url, device: device, watchesSource: false)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

enum Shaders {
    static func solid(_ r: Double, _ g: Double, _ b: Double) -> String {
        """
        fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
            return float4(\(r), \(g), \(b), 1.0);
        }
        """
    }

    static let uv = """
    fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        return float4(in.uv.x, in.uv.y, 0.0, 1.0);
    }
    """

    static let uniforms = """
    fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        return float4(u.time / 4.0, u.resolution.x / 400.0, u.resolution.y / 400.0, 1.0);
    }
    """

    static let brokenOnLine3 = """
    fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float x = 1.0;
        return float4(undefinedThing, x, 0.0, 1.0);
    }
    """

    static let wrongName = """
    fragment float4 notWallpaper(VertexOut in [[stage_in]]) {
        return float4(1.0);
    }
    """
}

struct RGBA: Equatable {
    let r: Int
    let g: Int
    let b: Int
}

func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
    let data = image.dataProvider!.data! as Data
    let offset = y * image.bytesPerRow + x * 4
    return RGBA(r: Int(data[offset + 2]), g: Int(data[offset + 1]), b: Int(data[offset]))
}

func isClose(_ value: Int, to expected: Int, within tolerance: Int = 3) -> Bool {
    abs(value - expected) <= tolerance
}

@MainActor
struct MetalRendererTests {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 0, y: 0, width: 1710, height: 1112))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 1710, y: 0, width: 2560, height: 1440))

    @Test func compilesAValidShader() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let renderer = try file.makeRenderer()

        try await renderer.load()

        #expect(renderer.pipeline != nil)
    }

    @Test func reportsCompileErrorsWithTheUsersLineNumber() async throws {
        let file = try ShaderFile(Shaders.brokenOnLine3)
        defer { file.remove() }
        let renderer = try file.makeRenderer()

        do {
            try await renderer.load()
            Issue.record("Expected a compile error")
        } catch {
            #expect(error.localizedDescription.contains("line 3:"), "Got: \(error.localizedDescription)")
            #expect(error.localizedDescription.contains("undefinedThing"))
        }
    }

    @Test func reportsAMissingWallpaperFunction() async throws {
        let file = try ShaderFile(Shaders.wrongName)
        defer { file.remove() }
        let renderer = try file.makeRenderer()

        await #expect(throws: (any Error).self) {
            try await renderer.load()
        }
    }

    @Test func eachDisplayGetsItsOwnView() async throws {
        let file = try ShaderFile(Shaders.solid(0, 0, 1))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()

        let first = try #require(renderer.attach(to: laptop) as? MTKView)
        let second = try #require(renderer.attach(to: external) as? MTKView)

        #expect(first !== second)
        #expect(first.preferredFramesPerSecond == 30)
        #expect(first.isPaused)
        renderer.play()
        #expect(!first.isPaused && !second.isPaused)
        renderer.tearDown()
        #expect(renderer.attachedDisplayIDs.isEmpty)
    }

    @Test func brokenEditKeepsTheOldShaderAndReportsAProblem() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()
        let original = try #require(renderer.pipeline)
        var reports: [String?] = []
        renderer.onProblem = { reports.append($0) }

        try file.write(Shaders.brokenOnLine3)
        await renderer.reloadIfChanged()

        #expect(renderer.pipeline === original)
        #expect(reports.count == 1)
        #expect(reports.first??.contains("line 3:") == true)
    }

    @Test func fixedEditSwapsTheShaderAndClearsTheProblem() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()
        let original = try #require(renderer.pipeline)
        var reports: [String?] = []
        renderer.onProblem = { reports.append($0) }

        try file.write(Shaders.brokenOnLine3)
        await renderer.reloadIfChanged()
        try file.write(Shaders.solid(0, 1, 0))
        await renderer.reloadIfChanged()

        #expect(renderer.pipeline !== original)
        #expect(reports.count == 2)
        #expect(reports.last! == nil)
        let image = try renderer.snapshot(width: 8, height: 8, time: 0)
        #expect(pixel(image, x: 4, y: 4) == RGBA(r: 0, g: 255, b: 0))
    }

    @Test func unchangedSourceDoesNotRecompile() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()
        let original = try #require(renderer.pipeline)

        await renderer.reloadIfChanged()

        #expect(renderer.pipeline === original)
    }

    @Test func snapshotRendersTheShader() async throws {
        let file = try ShaderFile(Shaders.solid(1, 0, 0))
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()

        let image = try renderer.snapshot(width: 16, height: 16, time: 0)

        #expect(image.width == 16 && image.height == 16)
        #expect(pixel(image, x: 8, y: 8) == RGBA(r: 255, g: 0, b: 0))
    }

    @Test func uvOriginIsBottomLeft() async throws {
        let file = try ShaderFile(Shaders.uv)
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()

        let image = try renderer.snapshot(width: 100, height: 100, time: 0)
        let topLeft = pixel(image, x: 0, y: 0)
        let bottomRight = pixel(image, x: 99, y: 99)

        #expect(topLeft.r < 5 && topLeft.g > 250)
        #expect(bottomRight.r > 250 && bottomRight.g < 5)
    }

    @Test func passesTimeAndResolutionToTheShader() async throws {
        let file = try ShaderFile(Shaders.uniforms)
        defer { file.remove() }
        let renderer = try file.makeRenderer()
        try await renderer.load()

        let image = try renderer.snapshot(width: 200, height: 100, time: 2)
        let color = pixel(image, x: 10, y: 10)

        #expect(isClose(color.r, to: 128))
        #expect(isClose(color.g, to: 128))
        #expect(isClose(color.b, to: 64))
    }
}

import Foundation
import Testing
@testable import Moonlet

struct InvalidManifestCase: Sendable, CustomTestStringConvertible {
    let label: String
    let manifest: String?
    let files: [String]
    let expectedMessage: String

    var testDescription: String { label }
}

struct WallpaperManifestTests {
    @Test func parsesAFullVideoManifest() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addWallpaper(
            "rain-window",
            manifest: """
            { "name": "Rain on Window", "type": "video", "source": "rain.mp4",
              "soundtrack": "rain.m4a", "volume": 0.8 }
            """,
            files: ["rain.mp4", "rain.m4a"]
        )

        let wallpaper = try WallpaperManifestParser.parse(folder: folder).get()

        #expect(wallpaper.id == "rain-window")
        #expect(wallpaper.name == "Rain on Window")
        #expect(wallpaper.kind == .video)
        #expect(wallpaper.source == .file(folder.appending(path: "rain.mp4")))
        #expect(wallpaper.soundtrack == .file(folder.appending(path: "rain.m4a")))
        #expect(wallpaper.volume == 0.8)
    }

    @Test func defaultsVolumeAndSoundtrack() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addVideo("plain", name: "Plain")

        let wallpaper = try WallpaperManifestParser.parse(folder: folder).get()

        #expect(wallpaper.volume == 1)
        #expect(wallpaper.soundtrack == nil)
    }

    @Test func acceptsTheVideosOwnAudioAsSoundtrack() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addWallpaper(
            "beach",
            manifest: #"{ "name": "Beach", "type": "video", "source": "beach.mov", "soundtrack": "video" }"#,
            files: ["beach.mov"]
        )

        let wallpaper = try WallpaperManifestParser.parse(folder: folder).get()

        #expect(wallpaper.soundtrack == .videoTrack)
    }

    @Test func acceptsARemoteURLForWebWallpapers() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addWallpaper(
            "clock",
            manifest: #"{ "name": "Clock", "type": "web", "source": "https://example.com/clock" }"#
        )

        let wallpaper = try WallpaperManifestParser.parse(folder: folder).get()

        #expect(wallpaper.source == .remote(URL(string: "https://example.com/clock")!))
    }

    @Test func acceptsLocalFilesForMetalAndWeb() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let metal = try library.addWallpaper(
            "aurora",
            manifest: #"{ "name": "Aurora", "type": "metal", "source": "aurora.metal" }"#,
            files: ["aurora.metal"]
        )
        let web = try library.addWallpaper(
            "page",
            manifest: #"{ "name": "Page", "type": "web", "source": "index.html" }"#,
            files: ["index.html"]
        )

        #expect(try WallpaperManifestParser.parse(folder: metal).get().kind == .metal)
        #expect(try WallpaperManifestParser.parse(folder: web).get().source == .file(web.appending(path: "index.html")))
    }

    @Test func readsAnOptionalRenderScale() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let scaled = try library.addWallpaper(
            "nebula",
            manifest: #"{ "name": "Nebula", "type": "metal", "source": "n.metal", "renderScale": 0.5 }"#,
            files: ["n.metal"]
        )
        let plain = try library.addVideo("plain", name: "Plain")

        #expect(try WallpaperManifestParser.parse(folder: scaled).get().renderScale == 0.5)
        #expect(try WallpaperManifestParser.parse(folder: plain).get().renderScale == 1)
    }

    @Test func readsAnOptionalImageForMetal() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addWallpaper(
            "canopy",
            manifest: #"{ "name": "Canopy", "type": "metal", "source": "c.metal", "image": "canopy.jpg" }"#,
            files: ["c.metal", "canopy.jpg"]
        )
        let plain = try library.addVideo("plain", name: "Plain")

        #expect(try WallpaperManifestParser.parse(folder: folder).get().image == folder.appending(path: "canopy.jpg"))
        #expect(try WallpaperManifestParser.parse(folder: plain).get().image == nil)
    }

    @Test func readsAnOptionalPixelatedFlag() throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let pixelated = try library.addWallpaper(
            "leaves",
            manifest: #"{ "name": "Leaves", "type": "metal", "source": "l.metal", "pixelated": true }"#,
            files: ["l.metal"]
        )
        let plain = try library.addWallpaper(
            "aurora",
            manifest: #"{ "name": "Aurora", "type": "metal", "source": "a.metal" }"#,
            files: ["a.metal"]
        )

        #expect(try WallpaperManifestParser.parse(folder: pixelated).get().pixelated)
        #expect(try !WallpaperManifestParser.parse(folder: plain).get().pixelated)
    }

    static let invalidCases: [InvalidManifestCase] = [
        .init(label: "no manifest", manifest: nil, files: [], expectedMessage: "Missing wallpaper.json"),
        .init(label: "bad JSON", manifest: "{ name: ", files: [], expectedMessage: "not valid JSON"),
        .init(label: "missing name", manifest: #"{ "type": "video", "source": "a.mp4" }"#, files: ["a.mp4"], expectedMessage: #"Missing "name""#),
        .init(label: "empty name", manifest: #"{ "name": " ", "type": "video", "source": "a.mp4" }"#, files: ["a.mp4"], expectedMessage: #"Missing "name""#),
        .init(label: "missing type", manifest: #"{ "name": "A", "source": "a.mp4" }"#, files: ["a.mp4"], expectedMessage: #"Missing "type""#),
        .init(label: "unknown type", manifest: #"{ "name": "A", "type": "gif", "source": "a.gif" }"#, files: ["a.gif"], expectedMessage: #"Unknown type "gif""#),
        .init(label: "missing source", manifest: #"{ "name": "A", "type": "video" }"#, files: [], expectedMessage: #"Missing "source""#),
        .init(label: "source not found", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4" }"#, files: [], expectedMessage: "not found"),
        .init(label: "URL for video", manifest: #"{ "name": "A", "type": "video", "source": "https://example.com/a.mp4" }"#, files: [], expectedMessage: "Only web wallpapers"),
        .init(label: "wrong extension", manifest: #"{ "name": "A", "type": "metal", "source": "a.mp4" }"#, files: ["a.mp4"], expectedMessage: ".metal"),
        .init(label: "escapes folder", manifest: #"{ "name": "A", "type": "video", "source": "../a.mp4" }"#, files: [], expectedMessage: "inside the wallpaper folder"),
        .init(label: "video soundtrack on metal", manifest: #"{ "name": "A", "type": "metal", "source": "a.metal", "soundtrack": "video" }"#, files: ["a.metal"], expectedMessage: "only works for video"),
        .init(label: "soundtrack not found", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "soundtrack": "a.m4a" }"#, files: ["a.mp4"], expectedMessage: "not found"),
        .init(label: "soundtrack not audio", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "soundtrack": "a.txt" }"#, files: ["a.mp4", "a.txt"], expectedMessage: "audio file"),
        .init(label: "volume too high", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "volume": 1.5 }"#, files: ["a.mp4"], expectedMessage: "between 0 and 1"),
        .init(label: "render scale too small", manifest: #"{ "name": "A", "type": "metal", "source": "a.metal", "renderScale": 0.1 }"#, files: ["a.metal"], expectedMessage: #""renderScale" must be between 0.25 and 1"#),
        .init(label: "image on video", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "image": "a.png" }"#, files: ["a.mp4", "a.png"], expectedMessage: #""image" only works for metal"#),
        .init(label: "image not found", manifest: #"{ "name": "A", "type": "metal", "source": "a.metal", "image": "a.png" }"#, files: ["a.metal"], expectedMessage: #"Image file "a.png" not found"#),
        .init(label: "image not a picture", manifest: #"{ "name": "A", "type": "metal", "source": "a.metal", "image": "a.txt" }"#, files: ["a.metal", "a.txt"], expectedMessage: "png, jpg, or heic"),
        .init(label: "pixelated on video", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "pixelated": true }"#, files: ["a.mp4"], expectedMessage: #""pixelated" only works for metal"#),
        .init(label: "volume wrong type", manifest: #"{ "name": "A", "type": "video", "source": "a.mp4", "volume": "loud" }"#, files: ["a.mp4"], expectedMessage: #""volume" has the wrong type"#),
    ]

    @Test(arguments: invalidCases)
    func reportsInvalidManifests(_ testCase: InvalidManifestCase) throws {
        let library = try TestLibraryFolder()
        defer { library.remove() }
        let folder = try library.addWallpaper("broken", manifest: testCase.manifest, files: testCase.files)

        let result = WallpaperManifestParser.parse(folder: folder)

        guard case .failure(let problem) = result else {
            Issue.record("Expected a failure for \(testCase.label)")
            return
        }
        #expect(problem.message.contains(testCase.expectedMessage), "Got: \(problem.message)")
    }
}

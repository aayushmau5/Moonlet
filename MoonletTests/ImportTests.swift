import Foundation
import Testing
@testable import Moonlet

final class ScratchFiles {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "moonlet-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(_ name: String, contents: String = "data") throws -> URL {
        let url = folder.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

struct SlugTests {
    @Test(arguments: [
        ("Rain on Window", "rain-on-window"),
        ("  Neon_City!! 2  ", "neon-city-2"),
        ("Café Night", "caf-night"),
        ("***", "wallpaper"),
    ])
    func makesFolderNames(input: String, expected: String) {
        #expect(LibraryImporter.slug(for: input) == expected)
    }

    @Test func addsANumberWhenTheNameIsTaken() {
        let taken: Set<String> = ["rain", "rain-2"]
        #expect(LibraryImporter.uniqueName("rain") { taken.contains($0) } == "rain-3")
        #expect(LibraryImporter.uniqueName("snow") { taken.contains($0) } == "snow")
    }
}

struct WallpaperImportTests {
    func manifest(in folder: URL) throws -> [String: String] {
        let data = try Data(contentsOf: folder.appending(path: "wallpaper.json"))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    @Test(arguments: [
        ("Rain on Window.mp4", "rain-on-window", "video"),
        ("Aurora.metal", "aurora", "metal"),
        ("clock.html", "clock", "web"),
    ])
    func importsEachKindWithAManifest(fileName: String, folderName: String, type: String) throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        let source = try scratch.file(fileName)

        let result = LibraryImporter.importWallpapers([source], into: library.wallpapersURL)

        let folder = library.wallpapersURL.appending(path: folderName)
        #expect(result.imported == [folderName])
        #expect(result.skipped.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: fileName).path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        let fields = try manifest(in: folder)
        #expect(fields["name"] == (fileName as NSString).deletingPathExtension)
        #expect(fields["type"] == type)
        #expect(fields["source"] == fileName)
        #expect(WallpaperManifestParser.parse(folder: folder).isSuccess)
    }

    @Test func avoidsTakenFolderNames() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        try library.addVideo("rain", name: "Rain")

        let result = LibraryImporter.importWallpapers([try scratch.file("rain.mov")], into: library.wallpapersURL)

        #expect(result.imported == ["rain-2"])
    }

    @Test func copiesAWallpaperFolderAsItIs() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        let folder = scratch.folder.appending(path: "My Shader")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{ "name": "Mine", "type": "metal", "source": "s.metal" }"#
            .write(to: folder.appending(path: "wallpaper.json"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appending(path: "s.metal"), atomically: true, encoding: .utf8)

        let result = LibraryImporter.importWallpapers([folder], into: library.wallpapersURL)

        #expect(result.imported == ["my-shader"])
        let copied = library.wallpapersURL.appending(path: "my-shader")
        #expect(FileManager.default.fileExists(atPath: copied.appending(path: "s.metal").path))
        #expect(try manifest(in: copied)["name"] == "Mine")
    }

    @Test func skipsWhatItCannotUse() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        let plainFolder = scratch.folder.appending(path: "Photos")
        try FileManager.default.createDirectory(at: plainFolder, withIntermediateDirectories: true)

        let result = LibraryImporter.importWallpapers(
            [try scratch.file("notes.txt"), try scratch.file("song.mp3"), plainFolder],
            into: library.wallpapersURL
        )

        #expect(result.imported.isEmpty)
        #expect(result.skipped == [
            "notes.txt: not a video, shader, or web page",
            "song.mp3: drop audio on a playlist in the Music tab",
            "Photos: the folder has no wallpaper.json",
        ])
    }
}

struct AudioImportTests {
    @Test func copiesAudioIntoAnExistingPlaylist() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        try library.addPlaylist("focus", files: ["a.mp3"])

        let result = LibraryImporter.importAudio(
            [try scratch.file("b.m4a"), try scratch.file("cover.jpg")],
            intoPlaylist: "focus",
            musicFolder: library.musicURL
        )

        #expect(result.imported == ["b.m4a"])
        #expect(result.skipped == ["cover.jpg: not an audio file"])
        #expect(FileManager.default.fileExists(atPath: library.musicURL.appending(path: "focus/b.m4a").path))
    }

    @Test func createsANewPlaylist() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }

        let result = LibraryImporter.importAudio([try scratch.file("one.flac")], intoPlaylist: " Late Night ", musicFolder: library.musicURL)

        #expect(result.imported == ["one.flac"])
        #expect(FileManager.default.fileExists(atPath: library.musicURL.appending(path: "Late Night/one.flac").path))
    }

    @Test func keepsBothFilesWhenNamesMatch() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }
        try library.addPlaylist("focus", files: ["a.mp3"])

        let result = LibraryImporter.importAudio([try scratch.file("a.mp3")], intoPlaylist: "focus", musicFolder: library.musicURL)

        #expect(result.imported == ["a 2.mp3"])
    }

    @Test func rejectsABadPlaylistName() throws {
        let scratch = try ScratchFiles()
        let library = try TestLibraryFolder()
        defer { scratch.remove(); library.remove() }

        let result = LibraryImporter.importAudio([try scratch.file("a.mp3")], intoPlaylist: "a/b", musicFolder: library.musicURL)

        #expect(result.imported.isEmpty)
        #expect(result.skipped == [#"a/b: a playlist name can't be empty or contain "/""#])
    }
}

@MainActor
struct IgnoreListTests {
    func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "moonlet-ignore-\(UUID().uuidString)")!
    }

    @Test func startsWithTheDefaults() {
        let list = IgnoreList(defaults: makeDefaults())
        #expect(list.bundleIDs == AppNaming.defaultIgnoredBundleIDs.sorted())
    }

    @Test func addsRemovesAndSaves() {
        let defaults = makeDefaults()
        let list = IgnoreList(defaults: defaults)
        var reported: [Set<String>] = []
        list.onChange = { reported.append($0) }

        list.add("com.spotify.client")
        list.add("com.spotify.client")
        list.remove("systemsoundserverd")

        #expect(list.bundleIDs == ["com.spotify.client", "com.vorssaint.utils"])
        #expect(IgnoreList(defaults: defaults).bundleIDs == ["com.spotify.client", "com.vorssaint.utils"])
        #expect(PlaybackMonitor.savedIgnoreList(in: defaults) == ["com.spotify.client", "com.vorssaint.utils"])
        #expect(reported.count == 2)
    }

    @Test func offersRunningAppsThatAreNotIgnoredYet() {
        let choices = IgnoreList.choices(
            from: [
                (name: "Spotify", bundleID: "com.spotify.client"),
                (name: "Moonlet", bundleID: "dev.moonlet.Moonlet"),
                (name: "Vorssaint", bundleID: "com.vorssaint.utils"),
                (name: "Nameless", bundleID: nil),
                (name: "Safari", bundleID: "com.apple.Safari"),
                (name: "Safari", bundleID: "com.apple.Safari"),
            ],
            ownBundleID: "dev.moonlet.Moonlet",
            ignored: ["com.vorssaint.utils"]
        )

        #expect(choices == [
            RunningApp(name: "Safari", bundleID: "com.apple.Safari"),
            RunningApp(name: "Spotify", bundleID: "com.spotify.client"),
        ])
    }
}

struct IgnoreMatchingTests {
    @Test func ignoringAnAppAlsoIgnoresItsHelpers() {
        let chromeHelper = AudioProcess(pid: 5, bundleID: "com.google.Chrome.helper", appName: nil, processName: nil)
        let safariMedia = AudioProcess(pid: 6, bundleID: "com.apple.WebKit.GPU", appName: "Safari Graphics and Media", processName: nil)

        #expect(AppNaming.isIgnored(chromeHelper, ownPID: 1, ignoredBundleIDs: ["com.google.Chrome"]))
        #expect(AppNaming.isIgnored(safariMedia, ownPID: 1, ignoredBundleIDs: [], ignoredAppNames: ["Safari"]))
        #expect(!AppNaming.isIgnored(safariMedia, ownPID: 1, ignoredBundleIDs: [], ignoredAppNames: ["Helium"]))
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

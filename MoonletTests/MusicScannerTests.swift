import Foundation
import Testing
@testable import Moonlet

extension TestLibraryFolder {
    var musicURL: URL {
        root.appending(path: "music", directoryHint: .isDirectory)
    }

    @discardableResult
    func addPlaylist(_ id: String, files: [String]) throws -> URL {
        let folder = musicURL.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: folder.appending(path: file))
        }
        return folder
    }

    func removePlaylist(_ id: String) throws {
        try FileManager.default.removeItem(at: musicURL.appending(path: id))
    }
}

@MainActor
struct MusicScannerTests {
    @Test func listsPlaylistsWithTracksInFilenameOrder() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addPlaylist("sleep", files: ["b.flac"])
        try folder.addPlaylist("focus", files: ["track10.mp3", "track2.mp3", "track1.m4a"])

        let result = MusicScanner.scan(musicFolder: folder.musicURL)

        #expect(result.playlists.map(\.id) == ["focus", "sleep"])
        #expect(result.playlists.first?.tracks.map(\.lastPathComponent) == ["track1.m4a", "track2.mp3", "track10.mp3"])
        #expect(result.problems.isEmpty)
    }

    @Test func ignoresNonAudioFilesHiddenFoldersAndLooseFiles() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addPlaylist("focus", files: ["song.mp3", "cover.jpg", "notes.txt", ".hidden.mp3"])
        try folder.addPlaylist(".secret", files: ["a.mp3"])
        try Data().write(to: folder.musicURL.appending(path: "loose.mp3"))

        let result = MusicScanner.scan(musicFolder: folder.musicURL)

        #expect(result.playlists.map(\.id) == ["focus"])
        #expect(result.playlists.first?.tracks.map(\.lastPathComponent) == ["song.mp3"])
    }

    @Test func reportsEmptyPlaylists() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addPlaylist("empty", files: ["readme.txt"])

        let result = MusicScanner.scan(musicFolder: folder.musicURL)

        #expect(result.playlists.isEmpty)
        #expect(result.problems == [Problem(location: "music/empty", message: "No audio files")])
    }

    @Test func libraryScanIncludesMusic() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addPlaylist("focus", files: ["a.mp3"])
        try folder.addPlaylist("empty", files: [])

        let library = Library(rootURL: folder.root)
        library.scan()

        #expect(library.playlists.map(\.id) == ["focus"])
        #expect(library.problems.map(\.location) == ["music/empty"])
    }
}

struct MusicSelectionTests {
    @Test(arguments: [
        (MusicSelection.none, "none"),
        (MusicSelection.playlist("focus"), "playlist:focus"),
    ])
    func roundTripsThroughStorage(selection: MusicSelection, stored: String) {
        #expect(selection.storageValue == stored)
        #expect(MusicSelection(storageValue: stored) == selection)
    }

    @Test func unknownStorageMeansNoSavedChoice() {
        #expect(MusicSelection(storageValue: nil) == nil)
        #expect(MusicSelection(storageValue: "garbage") == nil)
    }
}

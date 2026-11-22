import Foundation
import Testing
@testable import Moonlet

@MainActor
struct LibraryTests {
    @Test func listsValidWallpapersSortedByName() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("a-zebra", name: "Zebra")
        try folder.addVideo("b-apple", name: "apple")
        let library = Library(rootURL: folder.root)

        library.scan()

        #expect(library.wallpapers.map(\.id) == ["b-apple", "a-zebra"])
        #expect(library.problems.isEmpty)
    }

    @Test func reportsBrokenFoldersAndKeepsGoodOnes() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("good", name: "Good")
        try folder.addWallpaper("broken", manifest: "{ nope")
        try folder.addWallpaper("empty", manifest: nil)
        let library = Library(rootURL: folder.root)

        library.scan()

        #expect(library.wallpapers.map(\.id) == ["good"])
        #expect(library.problems.map(\.location) == ["wallpapers/broken", "wallpapers/empty"])
    }

    @Test func ignoresLooseFilesAndHiddenFolders() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("good", name: "Good")
        try folder.addVideo(".hidden", name: "Hidden")
        try Data().write(to: folder.wallpapersURL.appending(path: "notes.txt"))
        let library = Library(rootURL: folder.root)

        library.scan()

        #expect(library.wallpapers.map(\.id) == ["good"])
        #expect(library.problems.isEmpty)
    }

    @Test func createsTheWallpapersFolderWhenMissing() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        let library = Library(rootURL: folder.root)

        library.scan()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.wallpapersURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(library.wallpapers.isEmpty)
    }

    @Test func rescanReflectsRemovedWallpapers() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("one", name: "One")
        try folder.addVideo("two", name: "Two")
        let library = Library(rootURL: folder.root)
        library.scan()

        try folder.removeWallpaper("one")
        library.scan()

        #expect(library.wallpapers.map(\.id) == ["two"])
    }

    @Test func notifiesAfterEachScan() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        let library = Library(rootURL: folder.root)
        var calls = 0
        library.onChange = { calls += 1 }

        library.scan()
        library.scan()

        #expect(calls == 2)
    }

    @Test func findsWallpaperByID() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("one", name: "One")
        let library = Library(rootURL: folder.root)
        library.scan()

        #expect(library.wallpaper(withID: "one")?.name == "One")
        #expect(library.wallpaper(withID: "missing") == nil)
    }
}

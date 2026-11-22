import Foundation
import Observation
import os

@MainActor
@Observable
final class Library {
    static let defaultRootURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Moonlet", directoryHint: .isDirectory)

    let rootURL: URL
    private(set) var wallpapers: [Wallpaper] = []
    private(set) var playlists: [Playlist] = []
    private(set) var streams: [RadioStream] = []
    private(set) var packs: [Pack] = []
    private(set) var problems: [Problem] = []

    @ObservationIgnored private var changeHandlers: [() -> Void] = []
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "library")

    init(rootURL: URL = Library.defaultRootURL) {
        self.rootURL = rootURL
    }

    var wallpapersURL: URL {
        rootURL.appending(path: "wallpapers", directoryHint: .isDirectory)
    }

    var packsURL: URL {
        rootURL.appending(path: "packs", directoryHint: .isDirectory)
    }

    func pack(withID id: String) -> Pack? {
        packs.first { $0.id == id }
    }

    var musicURL: URL {
        rootURL.appending(path: "music", directoryHint: .isDirectory)
    }

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    func wallpaper(withID id: String) -> Wallpaper? {
        wallpapers.first { $0.id == id }
    }

    func scan() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: wallpapersURL, withIntermediateDirectories: true)

        var found: [Wallpaper] = []
        var issues: [Problem] = []
        for folder in wallpaperFolders() {
            switch WallpaperManifestParser.parse(folder: folder) {
            case .success(let wallpaper):
                found.append(wallpaper)
            case .failure(let problem):
                issues.append(Problem(location: "wallpapers/\(folder.lastPathComponent)", message: problem.message))
            }
        }

        let music = MusicScanner.scan(musicFolder: musicURL)
        let radio = StreamsFile.load(from: rootURL.appending(path: StreamsFile.fileName))
        let packScan = scanPacks(wallpaperIDs: Set(found.map(\.id)))
        wallpapers = found.sorted(by: Self.byName)
        playlists = music.playlists
        streams = radio.streams
        packs = packScan.packs
        problems = (issues + music.problems + packScan.problems).sorted { $0.location < $1.location } + radio.problems
        logger.info("Scanned \(found.count) wallpapers, \(music.playlists.count) playlists, \(self.problems.count) problems")
        changeHandlers.forEach { $0() }
    }

    func startWatching() {
        guard watcher == nil else { return }
        let watcher = FolderWatcher(url: rootURL) { [weak self] in
            Task { @MainActor in
                self?.scan()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func scanPacks(wallpaperIDs: Set<String>) -> (packs: [Pack], problems: [Problem]) {
        try? FileManager.default.createDirectory(at: packsURL, withIntermediateDirectories: true)
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: packsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.pathExtension.lowercased() == "json" }

        var packs: [Pack] = []
        var problems: [Problem] = []
        for file in files {
            let result = PackParser.parse(file: file, wallpaperIDs: wallpaperIDs)
            packs.append(contentsOf: result.pack.map { [$0] } ?? [])
            problems.append(contentsOf: result.problems)
        }
        packs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (packs, problems)
    }

    private func wallpaperFolders() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: wallpapersURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func byName(_ lhs: Wallpaper, _ rhs: Wallpaper) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order == .orderedSame {
            return lhs.id < rhs.id
        }
        return order == .orderedAscending
    }
}

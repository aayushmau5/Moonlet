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
    private(set) var problems: [Problem] = []

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "library")

    init(rootURL: URL = Library.defaultRootURL) {
        self.rootURL = rootURL
    }

    var wallpapersURL: URL {
        rootURL.appending(path: "wallpapers", directoryHint: .isDirectory)
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

        wallpapers = found.sorted(by: Self.byName)
        problems = issues.sorted { $0.location < $1.location }
        logger.info("Scanned \(found.count) wallpapers, \(issues.count) problems")
        onChange?()
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

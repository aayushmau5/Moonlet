import Foundation

enum MusicScanner {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav"]

    static func scan(musicFolder: URL) -> (playlists: [Playlist], problems: [Problem]) {
        try? FileManager.default.createDirectory(at: musicFolder, withIntermediateDirectories: true)

        var playlists: [Playlist] = []
        var problems: [Problem] = []
        for folder in visibleItems(in: musicFolder) where isDirectory(folder) {
            let tracks = visibleItems(in: folder)
                .filter { !isDirectory($0) && audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let playlist = Playlist(id: folder.lastPathComponent, tracks: tracks)
            if tracks.isEmpty {
                problems.append(Problem(location: playlist.location, message: "No audio files"))
            } else {
                playlists.append(playlist)
            }
        }

        playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (playlists, problems)
    }

    private static func visibleItems(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

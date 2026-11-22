import Foundation

struct ImportResult: Equatable {
    var imported: [String] = []
    var skipped: [String] = []

    var summary: String {
        var parts: [String] = []
        if !imported.isEmpty {
            parts.append("Added \(imported.joined(separator: ", ")).")
        }
        if !skipped.isEmpty {
            parts.append("Skipped \(skipped.joined(separator: "; ")).")
        }
        return parts.joined(separator: " ")
    }
}

enum LibraryImporter {
    private static let wallpaperTypes: [String: WallpaperKind] = [
        "mp4": .video,
        "mov": .video,
        "metal": .metal,
        "html": .web,
        "htm": .web,
    ]

    private struct Manifest: Encodable {
        let name: String
        let type: String
        let source: String
    }

    static func slug(for name: String) -> String {
        var result = ""
        for character in name.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                result.append(character)
            } else if character == " " || character == "_" || character == "-" {
                if !result.isEmpty, result.last != "-" {
                    result.append("-")
                }
            }
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        return result.isEmpty ? "wallpaper" : result
    }

    static func uniqueName(_ base: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(base) else { return base }
        var number = 2
        while isTaken("\(base)-\(number)") {
            number += 1
        }
        return "\(base)-\(number)"
    }

    static func importWallpapers(_ urls: [URL], into wallpapersFolder: URL) -> ImportResult {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: wallpapersFolder, withIntermediateDirectories: true)
        var result = ImportResult()

        for url in urls {
            let name = url.lastPathComponent
            let isTaken: (String) -> Bool = { fileManager.fileExists(atPath: wallpapersFolder.appending(path: $0).path) }

            if isDirectory(url) {
                guard fileManager.fileExists(atPath: url.appending(path: WallpaperManifestParser.fileName).path) else {
                    result.skipped.append("\(name): the folder has no wallpaper.json")
                    continue
                }
                let id = uniqueName(slug(for: name), isTaken: isTaken)
                do {
                    try fileManager.copyItem(at: url, to: wallpapersFolder.appending(path: id))
                    result.imported.append(id)
                } catch {
                    result.skipped.append("\(name): \(error.localizedDescription)")
                }
                continue
            }

            let fileExtension = url.pathExtension.lowercased()
            guard let kind = wallpaperTypes[fileExtension] else {
                let reason = MusicScanner.audioExtensions.contains(fileExtension)
                    ? "drop audio on a playlist in the Music tab"
                    : "not a video, shader, or web page"
                result.skipped.append("\(name): \(reason)")
                continue
            }

            let stem = url.deletingPathExtension().lastPathComponent
            let id = uniqueName(slug(for: stem), isTaken: isTaken)
            let folder = wallpapersFolder.appending(path: id, directoryHint: .isDirectory)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: folder.appending(path: name))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                let manifest = Manifest(name: stem, type: kind.rawValue, source: name)
                try encoder.encode(manifest).write(to: folder.appending(path: WallpaperManifestParser.fileName))
                result.imported.append(id)
            } catch {
                try? fileManager.removeItem(at: folder)
                result.skipped.append("\(name): \(error.localizedDescription)")
            }
        }
        return result
    }

    static func importAudio(_ urls: [URL], intoPlaylist playlistName: String, musicFolder: URL) -> ImportResult {
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            return ImportResult(skipped: [#"\#(playlistName): a playlist name can't be empty or contain "/""#])
        }

        let fileManager = FileManager.default
        let folder = musicFolder.appending(path: name, directoryHint: .isDirectory)
        var result = ImportResult()
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return ImportResult(skipped: ["\(name): \(error.localizedDescription)"])
        }

        for url in urls {
            guard MusicScanner.audioExtensions.contains(url.pathExtension.lowercased()) else {
                result.skipped.append("\(url.lastPathComponent): not an audio file")
                continue
            }
            let destinationName = uniqueFileName(url.lastPathComponent) {
                fileManager.fileExists(atPath: folder.appending(path: $0).path)
            }
            do {
                try fileManager.copyItem(at: url, to: folder.appending(path: destinationName))
                result.imported.append(destinationName)
            } catch {
                result.skipped.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private static func uniqueFileName(_ fileName: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(fileName) else { return fileName }
        let stem = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        var number = 2
        while isTaken("\(stem) \(number).\(fileExtension)") {
            number += 1
        }
        return "\(stem) \(number).\(fileExtension)"
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

import Foundation

struct ManifestProblem: Error, Equatable {
    let message: String
}

private struct RawManifest: Decodable {
    let name: String?
    let type: String?
    let source: String?
    let soundtrack: String?
    let volume: Double?
    let renderScale: Double?
}

enum WallpaperManifestParser {
    static let fileName = "wallpaper.json"

    private static let sourceExtensions: [WallpaperKind: Set<String>] = [
        .video: ["mp4", "mov"],
        .metal: ["metal"],
        .web: ["html", "htm"],
    ]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav"]

    static func parse(folder: URL) -> Result<Wallpaper, ManifestProblem> {
        Result { try parseOrThrow(folder: folder) }
            .mapError { $0 as? ManifestProblem ?? ManifestProblem(message: $0.localizedDescription) }
    }

    private static func parseOrThrow(folder: URL) throws -> Wallpaper {
        let raw = try readManifest(in: folder)

        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ManifestProblem(message: #"Missing "name""#)
        }
        guard let typeName = raw.type else {
            throw ManifestProblem(message: #"Missing "type""#)
        }
        guard let kind = WallpaperKind(rawValue: typeName) else {
            throw ManifestProblem(message: #"Unknown type "\#(typeName)". Use video, metal, or web."#)
        }
        guard let sourceValue = raw.source, !sourceValue.isEmpty else {
            throw ManifestProblem(message: #"Missing "source""#)
        }

        let source = try resolveSource(sourceValue, kind: kind, folder: folder)
        let soundtrack = try raw.soundtrack.map { try resolveSoundtrack($0, kind: kind, folder: folder) }
        let volume = raw.volume ?? 1
        guard (0...1).contains(volume) else {
            throw ManifestProblem(message: #""volume" must be between 0 and 1"#)
        }
        let renderScale = raw.renderScale ?? 1
        guard (0.25...1).contains(renderScale) else {
            throw ManifestProblem(message: #""renderScale" must be between 0.25 and 1"#)
        }

        return Wallpaper(
            id: folder.lastPathComponent,
            name: name,
            kind: kind,
            source: source,
            soundtrack: soundtrack,
            volume: volume,
            folder: folder,
            renderScale: renderScale
        )
    }

    private static func readManifest(in folder: URL) throws -> RawManifest {
        let manifestURL = folder.appending(path: fileName)
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ManifestProblem(message: "Missing \(fileName)")
        }
        do {
            return try JSONDecoder().decode(RawManifest.self, from: data)
        } catch DecodingError.typeMismatch(_, let context) {
            throw ManifestProblem(message: #""\#(fieldName(context))" has the wrong type"#)
        } catch {
            throw ManifestProblem(message: "\(fileName) is not valid JSON")
        }
    }

    private static func fieldName(_ context: DecodingError.Context) -> String {
        context.codingPath.last?.stringValue ?? "field"
    }

    private static func resolveSource(_ value: String, kind: WallpaperKind, folder: URL) throws -> WallpaperSource {
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            guard kind == .web else {
                throw ManifestProblem(message: "Only web wallpapers can use a URL as their source")
            }
            return .remote(url)
        }

        let file = try fileInside(folder, named: value, label: "Source")
        let allowed = sourceExtensions[kind] ?? []
        guard allowed.contains(file.pathExtension.lowercased()) else {
            let list = allowed.sorted().map { ".\($0)" }.joined(separator: " or ")
            throw ManifestProblem(message: "Source for a \(kind.rawValue) wallpaper must be \(list)")
        }
        return .file(file)
    }

    private static func resolveSoundtrack(_ value: String, kind: WallpaperKind, folder: URL) throws -> Soundtrack {
        if value == "video" {
            guard kind == .video else {
                throw ManifestProblem(message: #""soundtrack": "video" only works for video wallpapers"#)
            }
            return .videoTrack
        }

        let file = try fileInside(folder, named: value, label: "Soundtrack")
        guard audioExtensions.contains(file.pathExtension.lowercased()) else {
            throw ManifestProblem(message: "Soundtrack must be an audio file (mp3, m4a, aac, flac, or wav)")
        }
        return .file(file)
    }

    private static func fileInside(_ folder: URL, named name: String, label: String) throws -> URL {
        let folderPath = folder.standardizedFileURL.path
        let file = folder.appending(path: name).standardizedFileURL
        guard file.path.hasPrefix(folderPath + "/") else {
            throw ManifestProblem(message: "\(label) must be a file inside the wallpaper folder")
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ManifestProblem(message: #"\#(label) file "\#(name)" not found"#)
        }
        return file
    }
}

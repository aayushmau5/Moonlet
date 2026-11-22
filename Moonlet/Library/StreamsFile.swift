import Foundation

enum StreamsFile {
    static let fileName = "streams.json"

    private struct Entry: Decodable {
        let name: String?
        let url: String?
    }

    static func load(from file: URL) -> (streams: [RadioStream], problems: [Problem]) {
        guard FileManager.default.fileExists(atPath: file.path) else { return ([], []) }

        guard let data = try? Data(contentsOf: file) else {
            return ([], [problem("Could not read \(fileName)")])
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return ([], [problem(#"\#(fileName) is not valid. It must be a list of { "name", "url" } entries."#)])
        }

        var streams: [RadioStream] = []
        var problems: [Problem] = []
        for (offset, entry) in entries.enumerated() {
            guard let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                problems.append(problem(#"entry \#(offset + 1): missing "name""#))
                continue
            }
            guard let value = entry.url, !value.isEmpty else {
                problems.append(problem(#"\#(name): missing "url""#))
                continue
            }
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  url.host() != nil else {
                problems.append(problem("\(name): the URL must start with http:// or https://"))
                continue
            }
            guard !streams.contains(where: { $0.name == name }) else {
                problems.append(problem("\(name): the name is used twice"))
                continue
            }
            streams.append(RadioStream(name: name, url: url))
        }
        return (streams, problems)
    }

    private static func problem(_ message: String) -> Problem {
        Problem(location: fileName, message: message)
    }
}

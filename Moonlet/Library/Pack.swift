import Foundation

struct PackSlot: Equatable, Sendable {
    let minuteOfDay: Int
    let wallpaperID: String
}

enum PackMode: Equatable, Sendable {
    case timeOfDay([PackSlot])
    case timer(interval: TimeInterval, wallpapers: [String], shuffled: Bool)
}

struct Pack: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mode: PackMode

    var location: String { "packs/\(id).json" }

    var summary: String {
        switch mode {
        case .timeOfDay:
            return "By time"
        case .timer(let interval, _, let shuffled):
            let minutes = Int((interval / 60).rounded())
            let every = minutes == 1 ? "Every minute" : "Every \(minutes) min"
            return shuffled ? "\(every), shuffled" : every
        }
    }
}

enum PackParser {
    private struct RawSlot: Decodable {
        let from: String?
        let wallpaper: String?
    }

    private struct RawPack: Decodable {
        let name: String?
        let mode: String?
        let slots: [RawSlot]?
        let intervalMinutes: Double?
        let wallpapers: [String]?
        let order: String?
    }

    static func parse(file: URL, wallpaperIDs: Set<String>) -> (pack: Pack?, problems: [Problem]) {
        let id = file.deletingPathExtension().lastPathComponent
        let location = "packs/\(id).json"
        var problems: [String] = []
        let pack = build(id: id, file: file, wallpaperIDs: wallpaperIDs, problems: &problems)
        return (pack, problems.map { Problem(location: location, message: $0) })
    }

    private static func build(id: String, file: URL, wallpaperIDs: Set<String>, problems: inout [String]) -> Pack? {
        guard let data = try? Data(contentsOf: file),
              let raw = try? JSONDecoder().decode(RawPack.self, from: data) else {
            problems.append("\(file.lastPathComponent) is not valid JSON")
            return nil
        }
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            problems.append(#"Missing "name""#)
            return nil
        }
        guard let modeName = raw.mode else {
            problems.append(#"Missing "mode""#)
            return nil
        }

        let mode: PackMode?
        switch modeName {
        case "timeOfDay":
            mode = timeOfDay(raw.slots ?? [], wallpaperIDs: wallpaperIDs, problems: &problems)
        case "timer":
            mode = timer(raw, wallpaperIDs: wallpaperIDs, problems: &problems)
        default:
            problems.append(#"Unknown mode "\#(modeName)". Use timeOfDay or timer."#)
            return nil
        }
        return mode.map { Pack(id: id, name: name, mode: $0) }
    }

    private static func timeOfDay(_ rawSlots: [RawSlot], wallpaperIDs: Set<String>, problems: inout [String]) -> PackMode? {
        var slots: [PackSlot] = []
        for raw in rawSlots {
            let time = raw.from ?? ""
            guard let minute = minuteOfDay(time) else {
                problems.append(#"Slot "\#(time)": the time must look like 07:30"#)
                continue
            }
            guard let wallpaper = raw.wallpaper else {
                problems.append(#"Slot \#(time): missing "wallpaper""#)
                continue
            }
            guard wallpaperIDs.contains(wallpaper) else {
                problems.append(#"Slot \#(time): wallpaper "\#(wallpaper)" not found"#)
                continue
            }
            guard !slots.contains(where: { $0.minuteOfDay == minute }) else {
                problems.append("Slot \(time) is listed twice")
                continue
            }
            slots.append(PackSlot(minuteOfDay: minute, wallpaperID: wallpaper))
        }
        guard !slots.isEmpty else {
            problems.append("Nothing valid to show")
            return nil
        }
        return .timeOfDay(slots.sorted { $0.minuteOfDay < $1.minuteOfDay })
    }

    private static func timer(_ raw: RawPack, wallpaperIDs: Set<String>, problems: inout [String]) -> PackMode? {
        guard let minutes = raw.intervalMinutes, minutes >= 1 else {
            problems.append(#""intervalMinutes" must be at least 1"#)
            return nil
        }

        var shuffled = false
        switch raw.order ?? "sequential" {
        case "sequential":
            shuffled = false
        case "shuffle":
            shuffled = true
        case let other:
            problems.append(#"Unknown order "\#(other)". Use shuffle or sequential."#)
        }

        var wallpapers: [String] = []
        for id in raw.wallpapers ?? [] {
            guard wallpaperIDs.contains(id) else {
                problems.append(#"Wallpaper "\#(id)" not found"#)
                continue
            }
            wallpapers.append(id)
        }
        guard !wallpapers.isEmpty else {
            problems.append("Nothing valid to show")
            return nil
        }
        return .timer(interval: minutes * 60, wallpapers: wallpapers, shuffled: shuffled)
    }

    private static func minuteOfDay(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

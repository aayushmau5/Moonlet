import AppKit
import Observation

struct RunningApp: Identifiable, Hashable, Sendable {
    let name: String
    let bundleID: String

    var id: String { bundleID }
}

@MainActor
@Observable
final class IgnoreList {
    private(set) var bundleIDs: [String]

    @ObservationIgnored var onChange: ((Set<String>) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bundleIDs = PlaybackMonitor.savedIgnoreList(in: defaults).sorted()
    }

    func add(_ bundleID: String) {
        guard !bundleIDs.contains(bundleID) else { return }
        bundleIDs = (bundleIDs + [bundleID]).sorted()
        save()
    }

    func remove(_ bundleID: String) {
        guard bundleIDs.contains(bundleID) else { return }
        bundleIDs.removeAll { $0 == bundleID }
        save()
    }

    func runningChoices() -> [RunningApp] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { (name: $0.localizedName, bundleID: $0.bundleIdentifier) }
        return Self.choices(from: apps, ownBundleID: Bundle.main.bundleIdentifier ?? "", ignored: Set(bundleIDs))
    }

    static func choices(
        from apps: [(name: String?, bundleID: String?)],
        ownBundleID: String,
        ignored: Set<String>
    ) -> [RunningApp] {
        var seen: Set<String> = []
        var result: [RunningApp] = []
        for app in apps {
            guard let bundleID = app.bundleID, let name = app.name,
                  bundleID != ownBundleID, !ignored.contains(bundleID),
                  seen.insert(bundleID).inserted else { continue }
            result.append(RunningApp(name: name, bundleID: bundleID))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func appName(for bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
                FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
            }
    }

    private func save() {
        defaults.set(bundleIDs, forKey: PlaybackMonitor.ignoredBundleIDsKey)
        onChange?(Set(bundleIDs))
    }
}

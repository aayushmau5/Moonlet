import Foundation

struct AudioProcess: Equatable, Sendable {
    let pid: pid_t
    let bundleID: String
    let appName: String?
    let processName: String?
}

enum AppNaming {
    static let defaultIgnoredBundleIDs = ["systemsoundserverd", "com.vorssaint.utils"]

    private static let webKitHelperSuffix = " Graphics and Media"
    private static let helperBundleSuffix = ".helper"
    private static let ownHelperPrefix = "Moonlet "

    static func displayName(for process: AudioProcess, appNameForBundleID: (String) -> String?) -> String {
        if let appName = process.appName, appName.hasSuffix(webKitHelperSuffix) {
            return String(appName.dropLast(webKitHelperSuffix.count))
        }
        if process.bundleID.hasSuffix(helperBundleSuffix) {
            let parent = String(process.bundleID.dropLast(helperBundleSuffix.count))
            if let name = appNameForBundleID(parent) {
                return name
            }
        }
        if let appName = process.appName, !appName.isEmpty {
            return appName
        }
        if let processName = process.processName, !processName.isEmpty {
            return processName
        }
        return process.bundleID.isEmpty ? "Another app" : process.bundleID
    }

    static func isIgnored(_ process: AudioProcess, ownPID: pid_t, ignoredBundleIDs: Set<String>) -> Bool {
        process.pid == ownPID
            || ignoredBundleIDs.contains(process.bundleID)
            || (process.appName?.hasPrefix(ownHelperPrefix) ?? false)
    }
}

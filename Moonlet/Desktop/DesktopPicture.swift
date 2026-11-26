import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

@MainActor
final class DesktopPicture {
    static let keptStills = 2
    static let keptStillsWithoutStore = 20

    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Moonlet/Stills", directoryHint: .isDirectory)
    }

    private static let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true,
    ]

    private let folder: URL
    private let storeURL: URL
    private let workspace = NSWorkspace.shared
    private(set) var current: [CGDirectDisplayID: URL] = [:]
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "desktop-picture")

    init(
        folder: URL = DesktopPicture.defaultFolder,
        storeURL: URL = URL.applicationSupportDirectory.appending(path: "com.apple.wallpaper/Store/Index.plist")
    ) {
        self.folder = folder
        self.storeURL = storeURL
    }

    func start() {
        guard observer == nil else { return }
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyToScreens()
            }
        }
    }

    func stop() {
        observer.map(workspace.notificationCenter.removeObserver)
        observer = nil
    }

    func show(_ stills: [CGDirectDisplayID: CGImage]) async {
        for (id, image) in stills {
            do {
                let stamp = Int(Date().timeIntervalSince1970 * 1000)
                let url = folder.appending(path: "\(id)-\(stamp).jpg")
                let folder = folder
                try await Task.detached(priority: .utility) {
                    try Self.write(image, to: url, in: folder)
                }.value
                current[id] = url
                prune(id)
            } catch {
                logger.error("Could not save the still for screen \(id): \(error.localizedDescription, privacy: .public)")
            }
        }
        applyToScreens()
    }

    private func applyToScreens() {
        for (id, screen) in screensByID() {
            guard let url = current[id], workspace.desktopImageURL(for: screen) != url else { continue }
            do {
                try workspace.setDesktopImageURL(url, for: screen, options: Self.options)
            } catch {
                logger.error("Could not set the desktop picture for screen \(id): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func screensByID() -> [CGDirectDisplayID: NSScreen] {
        var screens: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = SystemDisplayProvider.displayID(of: screen) {
                screens[id] = screen
            }
        }
        return screens
    }

    nonisolated private static func write(_ image: CGImage, to url: URL, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: ".\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    private func prune(_ id: CGDirectDisplayID) {
        let key = URLResourceKey.contentModificationDateKey
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])) ?? []
        let stills = files
            .filter { $0.lastPathComponent.hasPrefix("\(id)-") }
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }

        guard let store = try? Data(contentsOf: storeURL) else {
            stills.dropFirst(Self.keptStillsWithoutStore).forEach { try? FileManager.default.removeItem(at: $0) }
            return
        }
        for still in stills.dropFirst(Self.keptStills) where store.range(of: Data(still.lastPathComponent.utf8)) == nil {
            try? FileManager.default.removeItem(at: still)
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

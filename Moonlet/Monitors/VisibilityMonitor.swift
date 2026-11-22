import AppKit
import os

@MainActor
final class VisibilityMonitor {
    var onChange: ((Set<CGDirectDisplayID>) -> Void)?
    private(set) var covered: Set<CGDirectDisplayID> = []

    private let displayProvider: DisplayProvider
    private let readWindows: () -> [WindowInfo]
    private let isOccluded: (CGDirectDisplayID) -> Bool
    private let pollInterval: Duration
    private let ownPID = getpid()
    private var signals: [CGDirectDisplayID: DelayedSignal] = [:]
    private var pollTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "visuals")

    init(
        displayProvider: DisplayProvider,
        readWindows: @escaping () -> [WindowInfo] = Coverage.onScreenWindows,
        isOccluded: @escaping (CGDirectDisplayID) -> Bool,
        pollInterval: Duration = .seconds(1)
    ) {
        self.displayProvider = displayProvider
        self.readWindows = readWindows
        self.isOccluded = isOccluded
        self.pollInterval = pollInterval
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                self?.check(at: .now)
                try? await Task.sleep(for: pollInterval)
            }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    func check(at now: ContinuousClock.Instant) {
        let displays = displayProvider.displays
        let windows = readWindows()
        let primaryHeight = (displays.first { $0.frame.origin == .zero } ?? displays.first)?.frame.height ?? 0

        var next: Set<CGDirectDisplayID> = []
        for display in displays {
            let visibleFrame = Coverage.windowServerRect(fromCocoa: display.visibleFrame, primaryScreenHeight: primaryHeight)
            let rawCovered = isOccluded(display.id)
                || Coverage.isCovered(visibleFrame: visibleFrame, windows: windows, ownPID: ownPID)
            var signal = signals[display.id] ?? DelayedSignal(onDelay: .seconds(1), offDelay: .zero)
            if signal.update(raw: rawCovered, at: now) {
                next.insert(display.id)
            }
            signals[display.id] = signal
        }
        signals = signals.filter { id, _ in displays.contains { $0.id == id } }

        guard next != covered else { return }
        covered = next
        logger.info("Covered screens: \(next.sorted().map(String.init).joined(separator: ","), privacy: .public)")
        onChange?(next)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check(at: .now)
            }
        }
        observers.append((center, observer))
    }
}

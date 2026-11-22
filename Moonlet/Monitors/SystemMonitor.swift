import AppKit

@MainActor
final class SystemMonitor {
    enum Condition: Hashable {
        case screenLocked
        case displayAsleep
        case macAsleep
    }

    var onChange: ((String?) -> Void)?
    private(set) var active: Set<Condition> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var pauseText: String? {
        if active.contains(.macAsleep) { return "Mac asleep" }
        if active.contains(.screenLocked) { return "screen locked" }
        if active.contains(.displayAsleep) { return "display asleep" }
        return nil
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .macAsleep, true)
        observe(workspace, NSWorkspace.didWakeNotification, .macAsleep, false)
        observe(workspace, NSWorkspace.screensDidSleepNotification, .displayAsleep, true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, .displayAsleep, false)

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false)
    }

    func set(_ condition: Condition, active isActive: Bool) {
        let before = pauseText
        if isActive {
            active.insert(condition)
        } else {
            active.remove(condition)
        }
        if pauseText != before {
            onChange?(pauseText)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ condition: Condition, _ isActive: Bool) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.set(condition, active: isActive)
            }
        }
        observers.append((center, observer))
    }
}

import Foundation

@MainActor
final class LowPowerMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        onChange?(isEnabled)
    }

    private func refresh() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        onChange?(enabled)
    }
}

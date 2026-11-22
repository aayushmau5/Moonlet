import Foundation

@MainActor
final class OtherAudioDetector {
    var onChange: ((String?) -> Void)?
    private let monitor: PlaybackMonitor
    private var signal = DelayedSignal(onDelay: .seconds(3), offDelay: .seconds(5))
    private var lastApp: String?
    private var reported: String?

    init(monitor: PlaybackMonitor) {
        self.monitor = monitor
    }

    func start() {
        monitor.onTick = { [weak self] app in
            self?.tick(app)
        }
        monitor.start()
    }

    private func tick(_ app: String?) {
        if let app {
            lastApp = app
        }
        let isOn = signal.update(raw: app != nil, at: .now)
        let next = isOn ? lastApp : nil
        guard next != reported else { return }
        reported = next
        onChange?(next)
    }
}

import AppKit
import os

@MainActor
final class PackScheduler {
    var onWallpaper: ((String) -> Void)?
    private(set) var pack: Pack?

    private let now: () -> Date
    private let calendar: Calendar
    private var rotation: TimerRotation?
    private var nextSwitch: Date?
    private var lastRequested: String?
    private var tickTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "packs")

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    func start(checkEvery interval: Duration = .seconds(15)) {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.tick()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func run(_ newPack: Pack?) {
        pack = newPack
        lastRequested = nil
        rotation = nil
        nextSwitch = nil
        guard let newPack else {
            logger.info("Pack stopped")
            return
        }
        if case .timer(let interval, let wallpapers, let shuffled) = newPack.mode {
            rotation = TimerRotation(wallpapers: wallpapers, shuffled: shuffled)
            nextSwitch = now().addingTimeInterval(interval)
        }
        logger.info("Pack \(newPack.id, privacy: .public) started")
        tick()
    }

    func tick() {
        guard let pack else { return }
        let target: String
        switch pack.mode {
        case .timeOfDay(let slots):
            let minute = PackSchedule.minuteOfDay(now(), calendar: calendar)
            target = PackSchedule.slot(in: slots, atMinute: minute).wallpaperID
        case .timer(let interval, _, _):
            guard var rotation else { return }
            if let nextSwitch, now() >= nextSwitch {
                _ = rotation.advance()
                self.rotation = rotation
                self.nextSwitch = now().addingTimeInterval(interval)
            }
            target = rotation.current
        }

        guard target != lastRequested else { return }
        lastRequested = target
        logger.info("Pack \(pack.id, privacy: .public) shows \(target, privacy: .public)")
        onWallpaper?(target)
    }
}

import AVFoundation
import os

struct RetryPolicy: Sendable {
    let delays: [Duration]
    let resetAfter: Duration

    static let standard = RetryPolicy(
        delays: [.seconds(2), .seconds(5), .seconds(15)],
        resetAfter: .seconds(30)
    )

    func delay(afterFailures failures: Int) -> Duration? {
        guard failures >= 1, failures <= delays.count else { return nil }
        return delays[failures - 1]
    }

    func shouldReset(afterHealthyFor healthy: Duration?) -> Bool {
        guard let healthy else { return false }
        return healthy >= resetAfter
    }
}

@MainActor
final class StreamChannel: AudioChannel {
    var onNowPlaying: ((String) -> Void)?
    var onProblem: ((String) -> Void)?
    private(set) var attemptCount = 0
    private(set) var hasStartedPlaying = false

    private let stream: RadioStream
    private let policy: RetryPolicy
    private let stallTimeout: Duration
    private let player = AVPlayer()
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "audio")
    private var failures = 0
    private var healthySince: ContinuousClock.Instant?
    private var wantsToPlay = false
    private var isStopped = false
    private var handledFailureItem: ObjectIdentifier?
    private var itemObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var notificationObservers: [NSObjectProtocol] = []
    private var retryTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    init(stream: RadioStream, policy: RetryPolicy = .standard, stallTimeout: Duration = .seconds(10)) {
        self.stream = stream
        self.policy = policy
        self.stallTimeout = stallTimeout
        player.allowsExternalPlayback = false
    }

    func load() async throws {
        observePlayer()
        startItem()
    }

    func play() {
        wantsToPlay = true
        player.play()
    }

    func pause() {
        wantsToPlay = false
        stallTask?.cancel()
        player.pause()
    }

    func stop() {
        isStopped = true
        wantsToPlay = false
        retryTask?.cancel()
        stallTask?.cancel()
        itemObservation = nil
        playerObservation = nil
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func startItem() {
        guard !isStopped else { return }
        attemptCount += 1
        let item = AVPlayerItem(url: stream.url)
        let itemID = ObjectIdentifier(item)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "the stream failed"
            Task { @MainActor in
                self?.handleFailure(of: itemID, message: message)
            }
        }
        player.replaceCurrentItem(with: item)
        if wantsToPlay {
            player.play()
        }
        onNowPlaying?(stream.name)
    }

    private func observePlayer() {
        guard playerObservation == nil else { return }
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.timeControlStatusChanged(status)
            }
        }

        let center = NotificationCenter.default
        let endings: [(Notification.Name, String)] = [
            (AVPlayerItem.failedToPlayToEndTimeNotification, "the stream failed"),
            (AVPlayerItem.didPlayToEndTimeNotification, "the stream ended"),
        ]
        for (name, message) in endings {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let item = notification.object as? AVPlayerItem else { return }
                let itemID = ObjectIdentifier(item)
                MainActor.assumeIsolated {
                    self?.handleFailure(of: itemID, message: message)
                }
            }
            notificationObservers.append(observer)
        }
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard !isStopped else { return }
        switch status {
        case .playing:
            stallTask?.cancel()
            hasStartedPlaying = true
            if healthySince == nil {
                healthySince = .now
            }
        case .waitingToPlayAtSpecifiedRate where wantsToPlay:
            let itemID = player.currentItem.map(ObjectIdentifier.init)
            stallTask?.cancel()
            stallTask = Task { [weak self, stallTimeout] in
                try? await Task.sleep(for: stallTimeout)
                guard !Task.isCancelled, let itemID else { return }
                self?.handleFailure(of: itemID, message: "the stream stalled")
            }
        default:
            break
        }
    }

    private func handleFailure(of itemID: ObjectIdentifier, message: String) {
        guard !isStopped,
              let current = player.currentItem,
              ObjectIdentifier(current) == itemID,
              handledFailureItem != itemID else { return }
        handledFailureItem = itemID
        stallTask?.cancel()

        let healthyFor = healthySince.map { ContinuousClock.now - $0 }
        if policy.shouldReset(afterHealthyFor: healthyFor) {
            failures = 0
        }
        healthySince = nil
        failures += 1

        guard let delay = policy.delay(afterFailures: failures) else {
            logger.error("Stream \(self.stream.name, privacy: .public): giving up after \(self.failures - 1) retries (\(message, privacy: .public))")
            stop()
            onProblem?("Stream stopped: \(message)")
            return
        }

        logger.info("Stream \(self.stream.name, privacy: .public): \(message, privacy: .public); retry \(self.failures) in \(delay.formatted(), privacy: .public)")
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.startItem()
        }
    }
}

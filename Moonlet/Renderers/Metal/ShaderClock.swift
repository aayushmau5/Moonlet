import Foundation

struct ShaderClock {
    private var accumulated: Duration = .zero
    private var resumedAt: ContinuousClock.Instant?

    mutating func resume(at now: ContinuousClock.Instant) {
        guard resumedAt == nil else { return }
        resumedAt = now
    }

    mutating func pause(at now: ContinuousClock.Instant) {
        guard let resumedAt else { return }
        accumulated += now - resumedAt
        self.resumedAt = nil
    }

    func elapsed(at now: ContinuousClock.Instant) -> Double {
        var total = accumulated
        if let resumedAt {
            total += now - resumedAt
        }
        let parts = total.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

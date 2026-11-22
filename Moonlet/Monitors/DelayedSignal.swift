import Foundation

struct DelayedSignal {
    let onDelay: Duration
    let offDelay: Duration
    private(set) var output = false
    private var raw = false
    private var rawSince: ContinuousClock.Instant?

    init(onDelay: Duration, offDelay: Duration) {
        self.onDelay = onDelay
        self.offDelay = offDelay
    }

    mutating func update(raw newRaw: Bool, at now: ContinuousClock.Instant) -> Bool {
        if newRaw != raw || rawSince == nil {
            raw = newRaw
            rawSince = now
        }
        let heldFor = now - (rawSince ?? now)
        if raw, !output, heldFor >= onDelay {
            output = true
        } else if !raw, output, heldFor >= offDelay {
            output = false
        }
        return output
    }
}

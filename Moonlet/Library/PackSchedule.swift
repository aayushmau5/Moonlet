import Foundation

enum Rotation {
    static func nextIndex(after current: Int, count: Int, shuffled: Bool) -> Int {
        guard count > 1 else { return 0 }
        guard shuffled else { return (current + 1) % count }
        let pick = Int.random(in: 0..<(count - 1))
        return pick >= current ? pick + 1 : pick
    }
}

enum PackSchedule {
    static func slot(in slots: [PackSlot], atMinute minute: Int) -> PackSlot {
        slots.last { $0.minuteOfDay <= minute } ?? slots[slots.count - 1]
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

struct TimerRotation {
    let wallpapers: [String]
    let shuffled: Bool
    private var index: Int

    init(wallpapers: [String], shuffled: Bool) {
        self.wallpapers = wallpapers
        self.shuffled = shuffled
        self.index = shuffled ? Int.random(in: 0..<wallpapers.count) : 0
    }

    var current: String {
        wallpapers[index]
    }

    mutating func advance() -> String {
        index = Rotation.nextIndex(after: index, count: wallpapers.count, shuffled: shuffled)
        return current
    }
}

import Foundation
import Testing
@testable import Moonlet

extension TestLibraryFolder {
    var packsURL: URL {
        root.appending(path: "packs", directoryHint: .isDirectory)
    }

    @discardableResult
    func addPack(_ id: String, json: String) throws -> URL {
        try FileManager.default.createDirectory(at: packsURL, withIntermediateDirectories: true)
        let file = packsURL.appending(path: "\(id).json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func removePack(_ id: String) throws {
        try FileManager.default.removeItem(at: packsURL.appending(path: "\(id).json"))
    }
}

struct InvalidPackCase: Sendable, CustomTestStringConvertible {
    let label: String
    let json: String
    let expectedMessages: [String]
    let keepsPack: Bool

    var testDescription: String { label }
}

struct PackParserTests {
    let ids: Set<String> = ["aurora", "clock", "orbit"]

    func parse(_ json: String) throws -> (pack: Pack?, problems: [Problem]) {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        let file = try folder.addPack("workday", json: json)
        return PackParser.parse(file: file, wallpaperIDs: ids)
    }

    @Test func parsesATimeOfDayPackWithSlotsInTimeOrder() throws {
        let result = try parse("""
        { "name": "Workday", "mode": "timeOfDay",
          "slots": [{ "from": "19:00", "wallpaper": "orbit" }, { "from": "07:30", "wallpaper": "aurora" }] }
        """)

        let pack = try #require(result.pack)
        #expect(pack.id == "workday")
        #expect(pack.name == "Workday")
        #expect(pack.mode == .timeOfDay([
            PackSlot(minuteOfDay: 7 * 60 + 30, wallpaperID: "aurora"),
            PackSlot(minuteOfDay: 19 * 60, wallpaperID: "orbit"),
        ]))
        #expect(result.problems.isEmpty)
    }

    @Test func parsesATimerPack() throws {
        let result = try parse("""
        { "name": "Evenings", "mode": "timer", "intervalMinutes": 30, "order": "shuffle",
          "wallpapers": ["aurora", "clock"] }
        """)

        #expect(result.pack?.mode == .timer(interval: 1800, wallpapers: ["aurora", "clock"], shuffled: true))
        #expect(result.problems.isEmpty)
    }

    @Test func timerOrderDefaultsToSequential() throws {
        let result = try parse(#"{ "name": "E", "mode": "timer", "intervalMinutes": 5, "wallpapers": ["aurora"] }"#)

        #expect(result.pack?.mode == .timer(interval: 300, wallpapers: ["aurora"], shuffled: false))
    }

    static let invalidCases: [InvalidPackCase] = [
        .init(label: "bad JSON", json: "{ nope", expectedMessages: ["not valid JSON"], keepsPack: false),
        .init(label: "missing name", json: #"{ "mode": "timer", "intervalMinutes": 5, "wallpapers": ["aurora"] }"#, expectedMessages: [#"Missing "name""#], keepsPack: false),
        .init(label: "missing mode", json: #"{ "name": "P" }"#, expectedMessages: [#"Missing "mode""#], keepsPack: false),
        .init(label: "unknown mode", json: #"{ "name": "P", "mode": "random" }"#, expectedMessages: [#"Unknown mode "random""#], keepsPack: false),
        .init(label: "bad time", json: #"{ "name": "P", "mode": "timeOfDay", "slots": [{ "from": "7pm", "wallpaper": "aurora" }, { "from": "09:00", "wallpaper": "clock" }] }"#, expectedMessages: [#"Slot "7pm": the time must look like 07:30"#], keepsPack: true),
        .init(label: "missing wallpaper id", json: #"{ "name": "P", "mode": "timeOfDay", "slots": [{ "from": "07:00", "wallpaper": "gone" }, { "from": "09:00", "wallpaper": "clock" }] }"#, expectedMessages: [#"Slot 07:00: wallpaper "gone" not found"#], keepsPack: true),
        .init(label: "duplicate slot", json: #"{ "name": "P", "mode": "timeOfDay", "slots": [{ "from": "07:00", "wallpaper": "aurora" }, { "from": "07:00", "wallpaper": "clock" }] }"#, expectedMessages: ["Slot 07:00 is listed twice"], keepsPack: true),
        .init(label: "short interval", json: #"{ "name": "P", "mode": "timer", "intervalMinutes": 0.5, "wallpapers": ["aurora"] }"#, expectedMessages: [#""intervalMinutes" must be at least 1"#], keepsPack: false),
        .init(label: "unknown order", json: #"{ "name": "P", "mode": "timer", "intervalMinutes": 5, "order": "backwards", "wallpapers": ["aurora"] }"#, expectedMessages: [#"Unknown order "backwards""#], keepsPack: true),
        .init(label: "timer missing id", json: #"{ "name": "P", "mode": "timer", "intervalMinutes": 5, "wallpapers": ["gone", "aurora"] }"#, expectedMessages: [#"Wallpaper "gone" not found"#], keepsPack: true),
        .init(label: "nothing valid", json: #"{ "name": "P", "mode": "timer", "intervalMinutes": 5, "wallpapers": ["gone"] }"#, expectedMessages: [#"Wallpaper "gone" not found"#, "Nothing valid to show"], keepsPack: false),
        .init(label: "no slots", json: #"{ "name": "P", "mode": "timeOfDay", "slots": [] }"#, expectedMessages: ["Nothing valid to show"], keepsPack: false),
    ]

    @Test(arguments: invalidCases)
    func reportsInvalidPacks(_ testCase: InvalidPackCase) throws {
        let result = try parse(testCase.json)

        #expect((result.pack != nil) == testCase.keepsPack)
        #expect(result.problems.map(\.location).allSatisfy { $0 == "packs/workday.json" })
        let messages = result.problems.map(\.message)
        for expected in testCase.expectedMessages {
            #expect(messages.contains { $0.contains(expected) }, "Got: \(messages)")
        }
    }

    @Test @MainActor func libraryScansPacksAgainstItsWallpapers() throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        try folder.addVideo("one", name: "One")
        try folder.addPack("solo", json: #"{ "name": "Solo", "mode": "timer", "intervalMinutes": 5, "wallpapers": ["one", "missing"] }"#)
        let library = Library(rootURL: folder.root)

        library.scan()

        #expect(library.packs.map(\.id) == ["solo"])
        #expect(library.pack(withID: "solo")?.name == "Solo")
        #expect(library.problems.map(\.location) == ["packs/solo.json"])
    }
}

struct PackScheduleTests {
    let slots = [
        PackSlot(minuteOfDay: 6 * 60, wallpaperID: "aurora"),
        PackSlot(minuteOfDay: 9 * 60, wallpaperID: "clock"),
        PackSlot(minuteOfDay: 18 * 60, wallpaperID: "orbit"),
    ]

    static let slotCases: [(Int, String)] = [
        (359, "orbit"),
        (360, "aurora"),
        (539, "aurora"),
        (540, "clock"),
        (1020, "clock"),
        (1439, "orbit"),
        (0, "orbit"),
    ]

    @Test(arguments: slotCases)
    func picksTheLatestSlotAtOrBeforeNow(minute: Int, expected: String) {
        #expect(PackSchedule.slot(in: slots, atMinute: minute).wallpaperID == expected)
    }

    @Test func sequentialRotationCycles() {
        var rotation = TimerRotation(wallpapers: ["a", "b", "c"], shuffled: false)

        #expect(rotation.current == "a")
        #expect([rotation.advance(), rotation.advance(), rotation.advance()] == ["b", "c", "a"])
    }

    @Test func shuffleNeverRepeatsBackToBack() {
        var rotation = TimerRotation(wallpapers: ["a", "b", "c"], shuffled: true)
        var previous = rotation.current
        for _ in 0..<50 {
            let next = rotation.advance()
            #expect(next != previous)
            previous = next
        }
    }
}

@MainActor
final class SchedulerClock {
    var now: Date
    let calendar: Calendar

    init(hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: hour, minute: minute))!
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }

    func makeScheduler() -> PackScheduler {
        PackScheduler(now: { [unowned self] in self.now }, calendar: calendar)
    }
}

@MainActor
struct PackSchedulerTests {
    let dayPack = Pack(id: "day", name: "Day", mode: .timeOfDay([
        PackSlot(minuteOfDay: 6 * 60, wallpaperID: "aurora"),
        PackSlot(minuteOfDay: 18 * 60, wallpaperID: "orbit"),
    ]))

    @Test func timeOfDayPackSwitchesAtTheBoundary() {
        let clock = SchedulerClock(hour: 17, minute: 59)
        let scheduler = clock.makeScheduler()
        var shown: [String] = []
        scheduler.onWallpaper = { shown.append($0) }

        scheduler.run(dayPack)
        scheduler.tick()
        clock.advance(minutes: 1)
        scheduler.tick()

        #expect(shown == ["aurora", "orbit"])
    }

    @Test func timerPackSwitchesAfterItsInterval() {
        let clock = SchedulerClock(hour: 12, minute: 0)
        let scheduler = clock.makeScheduler()
        var shown: [String] = []
        scheduler.onWallpaper = { shown.append($0) }
        let pack = Pack(id: "rotate", name: "Rotate", mode: .timer(interval: 600, wallpapers: ["a", "b"], shuffled: false))

        scheduler.run(pack)
        clock.advance(minutes: 9)
        scheduler.tick()
        clock.advance(minutes: 1)
        scheduler.tick()
        clock.advance(minutes: 10)
        scheduler.tick()

        #expect(shown == ["a", "b", "a"])
    }

    @Test func stoppingEndsTheSchedule() {
        let clock = SchedulerClock(hour: 17, minute: 59)
        let scheduler = clock.makeScheduler()
        var shown: [String] = []
        scheduler.onWallpaper = { shown.append($0) }
        scheduler.run(dayPack)

        scheduler.run(nil)
        clock.advance(minutes: 5)
        scheduler.tick()

        #expect(shown == ["aurora"])
        #expect(scheduler.pack == nil)
    }
}

@MainActor
struct PackSelectionTests {
    let packJSON = #"{ "name": "Rotate", "mode": "timer", "intervalMinutes": 10, "wallpapers": ["two", "one"] }"#

    func harness() throws -> (AppStateHarness, SchedulerClock) {
        let harness = try AppStateHarness()
        try harness.folder.addVideo("one", name: "One")
        try harness.folder.addVideo("two", name: "Two")
        try harness.folder.addPack("rotate", json: packJSON)
        return (harness, SchedulerClock(hour: 12, minute: 0))
    }

    @Test func pickingAPackStartsItAndRemembersIt() throws {
        let (harness, clock) = try harness()
        defer { harness.cleanUp() }
        let state = harness.makeState(scheduler: clock.makeScheduler())
        state.start(watching: false)

        state.selectPack("rotate")

        #expect(state.selectedPackID == "rotate")
        #expect(state.selectedWallpaperID == "two")
        #expect(harness.switcher.switched.last?.id == "two")
        #expect(harness.defaults.string(forKey: AppState.selectedPackKey) == "rotate")
    }

    @Test func aManualPickStopsThePack() throws {
        let (harness, clock) = try harness()
        defer { harness.cleanUp() }
        let scheduler = clock.makeScheduler()
        let state = harness.makeState(scheduler: scheduler)
        state.start(watching: false)
        state.selectPack("rotate")

        state.select("one")
        clock.advance(minutes: 20)
        scheduler.tick()

        #expect(state.selectedPackID == nil)
        #expect(harness.defaults.string(forKey: AppState.selectedPackKey) == nil)
        #expect(harness.switcher.switched.last?.id == "one")
    }

    @Test func theSavedPackResumesOnLaunchWithoutShowingTheOldWallpaperFirst() throws {
        let (harness, clock) = try harness()
        defer { harness.cleanUp() }
        harness.defaults.set("rotate", forKey: AppState.selectedPackKey)
        harness.defaults.set("one", forKey: AppState.selectedWallpaperKey)
        let state = harness.makeState(scheduler: clock.makeScheduler())

        state.start(watching: false)

        #expect(state.selectedPackID == "rotate")
        #expect(harness.switcher.switched.map(\.id) == ["two"])
    }

    @Test func ignoresUnknownPacks() throws {
        let (harness, clock) = try harness()
        defer { harness.cleanUp() }
        let state = harness.makeState(scheduler: clock.makeScheduler())
        state.start(watching: false)

        state.selectPack("missing")

        #expect(state.selectedPackID == nil)
    }

    @Test func aDeletedPackStopsButKeepsTheCurrentWallpaper() throws {
        let (harness, clock) = try harness()
        defer { harness.cleanUp() }
        let scheduler = clock.makeScheduler()
        let state = harness.makeState(scheduler: scheduler)
        state.start(watching: false)
        state.selectPack("rotate")

        try harness.folder.removePack("rotate")
        harness.library.scan()

        #expect(scheduler.pack == nil)
        #expect(state.selectedWallpaperID == "two")
        #expect(harness.switcher.switched.map(\.id).last == "two")
    }
}

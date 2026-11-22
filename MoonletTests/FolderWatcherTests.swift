import Foundation
import Testing
@testable import Moonlet

final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}

struct FolderWatcherTests {
    @Test func reportsAFileWrittenIntoTheFolder() async throws {
        let folder = try TestLibraryFolder()
        defer { folder.remove() }
        let counter = ChangeCounter()
        let watcher = FolderWatcher(url: folder.root, latency: 0.1) {
            counter.increment()
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(200))
        try Data("hello".utf8).write(to: folder.root.appending(path: "new.txt"))

        let deadline = ContinuousClock.now + .seconds(3)
        while counter.value == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(counter.value > 0)
    }
}

import AppKit
import Testing
import WebKit
@testable import Moonlet

@MainActor
final class WebPageFolder {
    let folder: URL
    let page: URL

    init(title: String) throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "moonlet-web-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        page = folder.appending(path: "index.html")
        try write(title: title)
    }

    func write(title: String) throws {
        let html = "<!doctype html><html><head><title>\(title)</title></head><body><p>\(title)</p></body></html>"
        try html.write(to: page, atomically: true, encoding: .utf8)
    }

    func makeRenderer() -> WebRenderer {
        WebRenderer(source: .file(page), folder: folder, watchesSource: false)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

@MainActor
func waitFor(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(30))
    }
}

@MainActor
struct WebRendererTests {
    let laptop = DisplayInfo(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let external = DisplayInfo(id: 2, frame: NSRect(x: 800, y: 0, width: 1024, height: 768))

    @Test func eachDisplayGetsItsOwnConfiguredWebView() async throws {
        let folder = try WebPageFolder(title: "One")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()

        let first = try #require(renderer.attach(to: laptop) as? WKWebView)
        let second = try #require(renderer.attach(to: external) as? WKWebView)

        #expect(first !== second)
        #expect(first.configuration.mediaTypesRequiringUserActionForPlayback == [])
        #expect(first.configuration.userContentController.userScripts.count == 2)
        renderer.tearDown()
        #expect(renderer.attachedDisplayIDs.isEmpty)
    }

    @Test func loadsTheLocalPage() async throws {
        let folder = try WebPageFolder(title: "Hello Moonlet")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        let view = try #require(renderer.attach(to: laptop) as? WKWebView)

        await renderer.waitUntilReady()

        #expect(view.title == "Hello Moonlet")
        renderer.tearDown()
    }

    @Test func loadFailsWhenThePageIsMissing() async throws {
        let folder = try WebPageFolder(title: "Gone")
        defer { folder.remove() }
        try FileManager.default.removeItem(at: folder.page)
        let renderer = folder.makeRenderer()

        await #expect(throws: (any Error).self) {
            try await renderer.load()
        }
    }

    @Test func reportsAPageThatFailsToLoad() async throws {
        let folder = try WebPageFolder(title: "Soon Gone")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        var reports: [String?] = []
        renderer.onProblem = { reports.append($0) }
        try FileManager.default.removeItem(at: folder.page)

        _ = renderer.attach(to: laptop)
        await waitFor { !reports.isEmpty }

        #expect(reports.first??.contains("Could not load page") == true)
        renderer.tearDown()
    }

    @Test func mutesMediaWhenItPlays() async throws {
        let folder = try WebPageFolder(title: "Media")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        let view = try #require(renderer.attach(to: laptop) as? WKWebView)
        await renderer.waitUntilReady()

        let muted = try await view.evaluateJavaScript("""
        (() => {
            const video = document.createElement('video');
            document.body.appendChild(video);
            video.dispatchEvent(new Event('play'));
            return video.muted;
        })()
        """)

        #expect(muted as? Bool == true)
        renderer.tearDown()
    }

    @Test func hidesScrollbars() async throws {
        let folder = try WebPageFolder(title: "Scroll")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        let view = try #require(renderer.attach(to: laptop) as? WKWebView)
        await renderer.waitUntilReady()

        let overflow = try await view.evaluateJavaScript("getComputedStyle(document.body).overflow")

        #expect(overflow as? String == "hidden")
        renderer.tearDown()
    }

    @Test func reloadShowsTheEditedPage() async throws {
        let folder = try WebPageFolder(title: "Before")
        defer { folder.remove() }
        let renderer = folder.makeRenderer()
        try await renderer.load()
        let view = try #require(renderer.attach(to: laptop) as? WKWebView)
        await renderer.waitUntilReady()

        try folder.write(title: "After")
        renderer.reloadPages()
        await waitFor { view.title == "After" }

        #expect(view.title == "After")
        renderer.tearDown()
    }
}

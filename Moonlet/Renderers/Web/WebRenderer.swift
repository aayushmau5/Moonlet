import AppKit
import WebKit
import os

struct WebRendererError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class WebRenderer: NSObject, WallpaperRenderer {
    var onProblem: ((String?) -> Void)?

    private let source: WallpaperSource
    private let folder: URL
    private let watchesSource: Bool
    private var views: [CGDirectDisplayID: WKWebView] = [:]
    private var loadedViews: Set<ObjectIdentifier> = []
    private var hasProblem = false
    private var watcher: FolderWatcher?
    private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "web")

    var attachedDisplayIDs: [CGDirectDisplayID] {
        Array(views.keys)
    }

    init(source: WallpaperSource, folder: URL, watchesSource: Bool = true) {
        self.source = source
        self.folder = folder
        self.watchesSource = watchesSource
        super.init()
    }

    func load() async throws {
        guard case .file(let page) = source else { return }
        guard FileManager.default.fileExists(atPath: page.path) else {
            throw WebRendererError(message: "Page \(page.lastPathComponent) not found")
        }
        if watchesSource {
            startWatching()
        }
    }

    func attach(to display: DisplayInfo) -> NSView {
        let view = WKWebView(
            frame: NSRect(origin: .zero, size: display.frame.size),
            configuration: WebPageScripts.makeConfiguration()
        )
        view.navigationDelegate = self
        view.underPageBackgroundColor = .black
        views[display.id] = view
        loadPage(in: view)
        return view
    }

    func detach(from displayID: CGDirectDisplayID) {
        guard let view = views.removeValue(forKey: displayID) else { return }
        view.stopLoading()
        view.navigationDelegate = nil
        loadedViews.remove(ObjectIdentifier(view))
    }

    func waitUntilReady() async {
        let deadline = ContinuousClock.now + .seconds(10)
        while let view = views.values.first,
              !loadedViews.contains(ObjectIdentifier(view)),
              !hasProblem,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    func play() {
        views.values.forEach { $0.setAllMediaPlaybackSuspended(false, completionHandler: nil) }
    }

    func pause() {
        views.values.forEach { $0.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
    }

    func tearDown() {
        watcher?.stop()
        watcher = nil
        for id in views.keys {
            detach(from: id)
        }
    }

    func reloadPages() {
        views.values.forEach(loadPage(in:))
    }

    private func loadPage(in view: WKWebView) {
        switch source {
        case .file(let page):
            view.loadFileURL(page, allowingReadAccessTo: folder)
        case .remote(let url):
            view.load(URLRequest(url: url))
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = FolderWatcher(url: folder, latency: 0.3) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.info("Reloading \(self.folder.lastPathComponent, privacy: .public) after a file change")
                self.reloadPages()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func pageFailed(_ error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        hasProblem = true
        onProblem?("Could not load page: \(error.localizedDescription)")
    }
}

extension WebRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadedViews.insert(ObjectIdentifier(webView))
        if hasProblem {
            hasProblem = false
            onProblem?(nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }
}

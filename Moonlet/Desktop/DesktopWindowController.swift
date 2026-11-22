import AppKit

@MainActor
final class DesktopWindowController: NSObject {
    private let displayProvider: DisplayProvider
    private(set) var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var renderer: WallpaperRenderer?
    private var rendererViews: [CGDirectDisplayID: NSView] = [:]
    private(set) var pausedDisplays: Set<CGDirectDisplayID> = []

    init(displayProvider: DisplayProvider) {
        self.displayProvider = displayProvider
        super.init()
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuild()
    }

    func displayedView(on displayID: CGDirectDisplayID) -> NSView? {
        rendererViews[displayID]
    }

    func setPausedDisplays(_ displays: Set<CGDirectDisplayID>) {
        pausedDisplays = displays
        renderer?.setPausedDisplays(displays)
    }

    func crossfade(to newRenderer: WallpaperRenderer, duration: TimeInterval) async {
        let oldRenderer = renderer
        renderer = newRenderer

        var fadingViews: [NSView] = []
        for display in displayProvider.displays {
            guard let container = windows[display.id]?.contentView else { continue }
            let view = install(newRenderer, on: display, in: container)
            view.alphaValue = 0
            fadingViews.append(view)
        }

        newRenderer.play()
        await newRenderer.waitUntilReady()
        await fadeIn(fadingViews, duration: duration)

        if let oldRenderer, oldRenderer !== newRenderer {
            oldRenderer.tearDown()
        }
        removeStaleViews()
        newRenderer.setPausedDisplays(pausedDisplays)
    }

    func rebuild() {
        let displays = displayProvider.displays
        let currentIDs = Set(displays.map(\.id))

        for (id, window) in windows where !currentIDs.contains(id) {
            renderer?.detach(from: id)
            rendererViews[id] = nil
            window.orderOut(nil)
            window.close()
            windows[id] = nil
        }

        for display in displays {
            if let window = windows[display.id] {
                window.setFrame(display.frame, display: true)
            } else {
                windows[display.id] = makeWindow(for: display)
            }
        }
    }

    func closeAll() {
        NotificationCenter.default.removeObserver(self)
        renderer?.tearDown()
        renderer = nil
        rendererViews.removeAll()
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func makeWindow(for display: DisplayInfo) -> NSWindow {
        let window = DesktopWindow(frame: display.frame)
        let container = NSView(frame: NSRect(origin: .zero, size: display.frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = container
        if let renderer {
            install(renderer, on: display, in: container)
            renderer.setPausedDisplays(pausedDisplays)
        }
        window.orderFrontRegardless()
        return window
    }

    @discardableResult
    private func install(_ renderer: WallpaperRenderer, on display: DisplayInfo, in container: NSView) -> NSView {
        let view = renderer.attach(to: display)
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        rendererViews[display.id] = view
        return view
    }

    private func fadeIn(_ views: [NSView], duration: TimeInterval) async {
        guard duration > 0, !views.isEmpty else {
            views.forEach { $0.alphaValue = 1 }
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for view in views {
                    view.animator().alphaValue = 1
                }
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    private func removeStaleViews() {
        for (id, window) in windows {
            guard let container = window.contentView else { continue }
            for subview in container.subviews where subview !== rendererViews[id] {
                subview.removeFromSuperview()
            }
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        rebuild()
    }
}

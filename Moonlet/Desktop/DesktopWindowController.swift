import AppKit

@MainActor
final class DesktopWindowController: NSObject {
    private let displayProvider: DisplayProvider
    private(set) var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var renderer: WallpaperRenderer?
    private var rendererViews: [CGDirectDisplayID: NSView] = [:]
    private(set) var pausedDisplays: Set<CGDirectDisplayID> = []
    private(set) var isWallpaperPaused = false
    private var isCrossfading = false
    private(set) var isParked = false

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

    func setWallpaperPaused(_ paused: Bool) {
        guard paused != isWallpaperPaused else { return }
        isWallpaperPaused = paused
        guard !isCrossfading, let renderer else { return }
        applyWallpaperPause(to: renderer)
    }

    func stills(on displayIDs: Set<CGDirectDisplayID>? = nil) async -> [CGDirectDisplayID: CGImage] {
        guard let renderer else { return [:] }
        var stills: [CGDirectDisplayID: CGImage] = [:]
        for id in windows.keys where displayIDs?.contains(id) ?? true {
            if let image = await renderer.still(on: id) {
                stills[id] = image
            }
        }
        return stills
    }

    func park(showing stills: [CGDirectDisplayID: CGImage], duration: TimeInterval) async {
        guard let parkedRenderer = renderer else { return }
        isParked = true
        for (id, window) in windows {
            guard let layer = window.contentView?.layer, let still = stills[id] else { continue }
            show(still, on: layer, duration: duration)
        }
        await fade(Array(rendererViews.values), to: 0, duration: duration)
        guard isParked, renderer === parkedRenderer else { return }
        parkedRenderer.tearDown()
        renderer = nil
        rendererViews.values.forEach { $0.removeFromSuperview() }
        rendererViews.removeAll()
    }

    func crossfade(to newRenderer: WallpaperRenderer, duration: TimeInterval) async {
        let oldRenderer = renderer
        renderer = newRenderer
        isCrossfading = true
        defer { isCrossfading = false }
        if isParked && isWallpaperPaused {
            await stageWhileParked(newRenderer, replacing: oldRenderer)
            return
        }
        isParked = false

        var fadingViews: [NSView] = []
        for display in displayProvider.displays {
            guard let container = windows[display.id]?.contentView else { continue }
            let view = install(newRenderer, on: display, in: container)
            view.alphaValue = 0
            fadingViews.append(view)
        }

        newRenderer.play()
        await newRenderer.waitUntilReady()
        await fade(fadingViews, to: 1, duration: duration)
        if !isParked {
            windows.values.forEach { $0.contentView?.layer?.contents = nil }
        }

        if let oldRenderer, oldRenderer !== newRenderer {
            oldRenderer.tearDown()
        }
        removeStaleViews()
        newRenderer.setPausedDisplays(pausedDisplays)
        applyWallpaperPause(to: newRenderer)
    }

    private func stageWhileParked(_ newRenderer: WallpaperRenderer, replacing oldRenderer: WallpaperRenderer?) async {
        if let oldRenderer, oldRenderer !== newRenderer {
            oldRenderer.tearDown()
        }
        for display in displayProvider.displays {
            guard let container = windows[display.id]?.contentView else { continue }
            install(newRenderer, on: display, in: container).alphaValue = 0
        }
        removeStaleViews()
        newRenderer.setPausedDisplays(pausedDisplays)
        newRenderer.pause()
        await newRenderer.waitUntilReady()
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

    private func applyWallpaperPause(to renderer: WallpaperRenderer) {
        if isWallpaperPaused {
            renderer.pause()
        } else {
            renderer.play()
        }
    }

    private func fade(_ views: [NSView], to alpha: CGFloat, duration: TimeInterval) async {
        await animate(duration: duration) { animated in
            views.forEach { (animated ? $0.animator() : $0).alphaValue = alpha }
        }
    }

    private func show(_ still: CGImage, on layer: CALayer, duration: TimeInterval) {
        if layer.contents != nil, duration > 0 {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = duration
            layer.add(transition, forKey: "still")
        }
        layer.contentsGravity = .resizeAspectFill
        layer.contents = still
    }

    private func animate(duration: TimeInterval, _ changes: @escaping (Bool) -> Void) async {
        guard duration > 0 else {
            changes(false)
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes(true)
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

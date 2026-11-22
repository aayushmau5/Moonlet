import AppKit

@MainActor
final class DesktopWindowController: NSObject {
    private let displayProvider: DisplayProvider
    private(set) var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var renderer: WallpaperRenderer?

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

    func show(_ newRenderer: WallpaperRenderer) {
        renderer?.tearDown()
        renderer = newRenderer
        for display in displayProvider.displays {
            windows[display.id]?.contentView = newRenderer.attach(to: display)
        }
        newRenderer.play()
    }

    func rebuild() {
        let displays = displayProvider.displays
        let currentIDs = Set(displays.map(\.id))

        for (id, window) in windows where !currentIDs.contains(id) {
            renderer?.detach(from: id)
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
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func makeWindow(for display: DisplayInfo) -> NSWindow {
        let window = DesktopWindow(frame: display.frame)
        if let renderer {
            window.contentView = renderer.attach(to: display)
        }
        window.orderFrontRegardless()
        return window
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        rebuild()
    }
}

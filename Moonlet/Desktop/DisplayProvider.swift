import AppKit

struct DisplayInfo: Equatable {
    let id: CGDirectDisplayID
    let frame: NSRect
    let visibleFrame: NSRect

    init(id: CGDirectDisplayID, frame: NSRect, visibleFrame: NSRect? = nil) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
    }
}

@MainActor
protocol DisplayProvider: AnyObject {
    var displays: [DisplayInfo] { get }
}

@MainActor
final class SystemDisplayProvider: DisplayProvider {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    var displays: [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = Self.displayID(of: screen) else { return nil }
            return DisplayInfo(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value
    }
}

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
            guard let number = screen.deviceDescription[Self.screenNumberKey] as? NSNumber else {
                return nil
            }
            return DisplayInfo(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }
}

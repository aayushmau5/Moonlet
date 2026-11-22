import CoreGraphics
import Foundation

struct WindowInfo: Equatable, Sendable {
    let bounds: CGRect
    let layer: Int
    let alpha: Double
    let ownerPID: pid_t
}

enum Coverage {
    static let threshold = 0.95

    static func windowServerRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    static func isCovered(visibleFrame: CGRect, windows: [WindowInfo], ownPID: pid_t) -> Bool {
        let area = visibleFrame.width * visibleFrame.height
        guard area > 0 else { return false }
        return windows.contains { window in
            guard window.layer == 0, window.alpha > 0, window.ownerPID != ownPID else { return false }
            let overlap = window.bounds.intersection(visibleFrame)
            guard !overlap.isNull else { return false }
            return Double((overlap.width * overlap.height) / area) >= threshold
        }
    }

    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            return WindowInfo(bounds: bounds, layer: layer, alpha: alpha, ownerPID: pid_t(pid))
        }
    }
}

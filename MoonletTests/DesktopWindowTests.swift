import AppKit
import Testing
@testable import Moonlet

@MainActor
struct DesktopWindowTests {
    let frame = NSRect(x: 100_000, y: 100_000, width: 1710, height: 1112)

    @Test func sitsAtDesktopLevel() {
        let window = DesktopWindow(frame: frame)
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        #expect(window.level.rawValue == desktopLevel)
    }

    @Test func joinsAllSpacesAndStaysPut() {
        let window = DesktopWindow(frame: frame)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.stationary))
        #expect(window.collectionBehavior.contains(.ignoresCycle))
    }

    @Test func letsClicksPassThrough() {
        let window = DesktopWindow(frame: frame)
        #expect(window.ignoresMouseEvents)
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
    }

    @Test func coversTheGivenFrame() {
        let window = DesktopWindow(frame: frame)
        #expect(window.frame == frame)
        #expect(!window.hasShadow)
        #expect(window.isOpaque)
    }
}

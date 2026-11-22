import AppKit

@MainActor
protocol WallpaperRenderer: AnyObject {
    func load() async throws
    func attach(to display: DisplayInfo) -> NSView
    func detach(from displayID: CGDirectDisplayID)
    func play()
    func pause()
    func tearDown()
}

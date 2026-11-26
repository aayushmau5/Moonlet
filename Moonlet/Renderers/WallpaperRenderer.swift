import AppKit

@MainActor
protocol WallpaperRenderer: AnyObject {
    var onProblem: ((String?) -> Void)? { get set }

    func load() async throws
    func attach(to display: DisplayInfo) -> NSView
    func detach(from displayID: CGDirectDisplayID)
    func waitUntilReady() async
    func play()
    func pause()
    func setPausedDisplays(_ displays: Set<CGDirectDisplayID>)
    func still(on displayID: CGDirectDisplayID) async -> CGImage?
    func tearDown()
}

import Foundation
import Observation
import os

@MainActor
protocol WallpaperSwitching: AnyObject {
    var requested: Wallpaper? { get }
    var problems: [Problem] { get }

    @discardableResult
    func switchTo(_ wallpaper: Wallpaper) -> Task<Void, Never>
}

@MainActor
@Observable
final class WallpaperSwitcher: WallpaperSwitching {
    typealias RendererMaker = @MainActor (Wallpaper) -> WallpaperRenderer?

    private(set) var requested: Wallpaper?
    private(set) var current: Wallpaper?
    private(set) var problems: [Problem] = []

    @ObservationIgnored var onShown: ((Wallpaper) -> Void)?
    @ObservationIgnored private let desktop: DesktopWindowController
    @ObservationIgnored private let fadeDuration: TimeInterval
    @ObservationIgnored private let makeRenderer: RendererMaker
    @ObservationIgnored private var lastTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.moonlet.Moonlet", category: "switcher")

    init(
        desktop: DesktopWindowController,
        fadeDuration: TimeInterval = 0.6,
        makeRenderer: @escaping RendererMaker = RendererFactory.makeRenderer(for:)
    ) {
        self.desktop = desktop
        self.fadeDuration = fadeDuration
        self.makeRenderer = makeRenderer
    }

    @discardableResult
    func switchTo(_ wallpaper: Wallpaper) -> Task<Void, Never> {
        requested = wallpaper
        let previous = lastTask
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.requested == wallpaper else { return }
            await self.perform(wallpaper)
        }
        lastTask = task
        return task
    }

    @discardableResult
    func replay() -> Task<Void, Never>? {
        guard let wallpaper = requested ?? current else { return nil }
        return switchTo(wallpaper)
    }

    private func perform(_ wallpaper: Wallpaper) async {
        guard let renderer = makeRenderer(wallpaper) else {
            fail(wallpaper, message: "\(wallpaper.kind.rawValue.capitalized) wallpapers are not supported yet")
            return
        }
        renderer.onProblem = { [weak self] message in
            self?.rendererReported(message, for: wallpaper)
        }

        do {
            try await renderer.load()
        } catch {
            renderer.tearDown()
            fail(wallpaper, message: "Could not load: \(error.localizedDescription)")
            return
        }

        guard requested == wallpaper else {
            renderer.tearDown()
            return
        }

        await desktop.crossfade(to: renderer, duration: fadeDuration)
        current = wallpaper
        problems.removeAll { $0.location == wallpaper.location }
        logger.info("Showing \(wallpaper.id, privacy: .public)")
        onShown?(wallpaper)
    }

    private func rendererReported(_ message: String?, for wallpaper: Wallpaper) {
        problems.removeAll { $0.location == wallpaper.location }
        if let message {
            logger.error("\(wallpaper.id, privacy: .public): \(message, privacy: .public)")
            problems.append(Problem(location: wallpaper.location, message: message))
        } else {
            logger.info("\(wallpaper.id, privacy: .public): problem cleared")
        }
    }

    private func fail(_ wallpaper: Wallpaper, message: String) {
        logger.error("\(wallpaper.id, privacy: .public): \(message, privacy: .public)")
        problems.removeAll { $0.location == wallpaper.location }
        problems.append(Problem(location: wallpaper.location, message: message))
        if requested == wallpaper {
            requested = current
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let testVideoURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Moonlet/wallpapers/test-gradient/gradient.mp4")

    var currentVideoURL: URL

    init(currentVideoURL: URL = AppState.testVideoURL) {
        self.currentVideoURL = currentVideoURL
    }
}

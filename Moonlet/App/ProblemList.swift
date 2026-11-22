import Foundation

@MainActor
enum ProblemList {
    static func combined(_ appState: AppState, _ audio: AudioController) -> [Problem] {
        (appState.problems + audio.problems).sorted { $0.location < $1.location }
    }
}

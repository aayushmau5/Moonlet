import SwiftUI

struct SettingsWindow: View {
    let appState: AppState
    let audio: AudioController
    let loginItem: LoginItem
    let thumbnails: Thumbnails
    let ignoreList: IgnoreList

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralTab(appState: appState, loginItem: loginItem)
            }
            Tab("Library", systemImage: "photo.on.rectangle") {
                LibraryTab(appState: appState, thumbnails: thumbnails)
            }
            Tab("Music", systemImage: "music.note") {
                MusicTab(library: appState.library, ignoreList: ignoreList)
            }
            Tab("Packs", systemImage: "square.stack") {
                PacksTab(appState: appState)
            }
            Tab("Problems", systemImage: "exclamationmark.triangle") {
                ProblemsTab(problems: ProblemList.combined(appState, audio))
            }
            .badge(ProblemList.combined(appState, audio).count)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(width: 680, height: 480)
    }
}

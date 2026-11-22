import SwiftUI

struct MenuContent: View {
    let appState: AppState

    var body: some View {
        let wallpapers = appState.library.wallpapers

        if wallpapers.isEmpty {
            Text("No wallpapers in ~/Moonlet/wallpapers")
        } else {
            ForEach(wallpapers) { wallpaper in
                wallpaperItem(wallpaper)
            }
        }

        let problems = appState.problems
        if !problems.isEmpty {
            Divider()
            Menu("Problems (\(problems.count))") {
                ForEach(problems) { problem in
                    Text("\(problem.location): \(problem.message)")
                }
            }
        }

        Divider()
        Button("Open Library Folder") {
            NSWorkspace.shared.open(appState.library.rootURL)
        }
        Button("Quit Moonlet") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func wallpaperItem(_ wallpaper: Wallpaper) -> some View {
        if appState.supports(wallpaper) {
            Toggle(wallpaper.name, isOn: Binding(
                get: { appState.selectedWallpaperID == wallpaper.id },
                set: { isOn in
                    if isOn {
                        appState.select(wallpaper.id)
                    }
                }
            ))
        } else {
            Text("\(wallpaper.name) (\(wallpaper.kind.rawValue), not supported yet)")
        }
    }
}

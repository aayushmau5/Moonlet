import SwiftUI

struct GeneralTab: View {
    let appState: AppState
    let loginItem: LoginItem

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                Text(loginItem.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let warning = loginItem.developmentWarning {
                    Label(warning, systemImage: "hammer")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let error = loginItem.errorText {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Playback") {
                Toggle("Pause live wallpaper in Low Power Mode", isOn: Binding(
                    get: { appState.pausesInLowPowerMode },
                    set: { appState.setPausesInLowPowerMode($0) }
                ))
                Text("Moonlet shows a still frame while Low Power Mode is on. Press Play in the menu to resume anyway.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Folder") {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Change…", action: chooseFolder)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.library.rootURL])
                    }
                }
                Text("Moonlet reads wallpapers, music, packs, and streams.json from this folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    private var displayPath: String {
        (appState.library.rootURL.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.library.rootURL
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder Moonlet should use as its library."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        appState.moveLibrary(to: folder)
    }
}

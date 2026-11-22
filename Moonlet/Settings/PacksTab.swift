import SwiftUI

struct PacksTab: View {
    let appState: AppState

    var body: some View {
        let packs = appState.library.packs
        if packs.isEmpty {
            ContentUnavailableView {
                Label("No packs", systemImage: "square.stack")
            } description: {
                Text("Add a .json file to the packs folder in your library.")
            } actions: {
                Button("Open Packs Folder", action: openFolder)
            }
        } else {
            Form {
                ForEach(packs) { pack in
                    Section {
                        entries(for: pack)
                    } header: {
                        HStack {
                            Text(pack.name)
                            if appState.selectedPackID == pack.id {
                                Text("Active")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            }
                            Spacer()
                            Text(pack.summary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Open Packs Folder", action: openFolder)
                } footer: {
                    Text("Packs are edited as JSON files. Moonlet reloads them when you save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func entries(for pack: Pack) -> some View {
        switch pack.mode {
        case .timeOfDay(let slots):
            ForEach(slots, id: \.minuteOfDay) { slot in
                LabeledContent(time(slot.minuteOfDay), value: name(of: slot.wallpaperID))
                    .monospacedDigit()
            }
        case .timer(_, let wallpapers, _):
            ForEach(Array(wallpapers.enumerated()), id: \.offset) { index, id in
                LabeledContent("\(index + 1)", value: name(of: id))
                    .monospacedDigit()
            }
        }
    }

    private func name(of wallpaperID: String) -> String {
        appState.library.wallpaper(withID: wallpaperID)?.name ?? wallpaperID
    }

    private func time(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    private func openFolder() {
        NSWorkspace.shared.open(appState.library.packsURL)
    }
}

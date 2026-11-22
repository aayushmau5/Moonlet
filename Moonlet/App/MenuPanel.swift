import SwiftUI

struct MenuPanel: View {
    let appState: AppState
    let audio: AudioController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WallpaperSection(appState: appState)
            Divider()
            MusicSection(audio: audio)
            if !problems.isEmpty {
                Divider()
                ProblemsSection(problems: problems)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var problems: [Problem] {
        ProblemList.combined(appState, audio)
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: MoonletApp.settingsWindowID)
                NSApplication.shared.activate()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(HoverButtonStyle())
        .font(.callout)
        .padding(.horizontal, -8)
    }
}

private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }
}

private struct HoverButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(highlight))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }

    private var highlight: Double {
        if configuration.isPressed { return 0.14 }
        return isHovered ? 0.08 : 0
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct WallpaperSection: View {
    static let maxListHeight: CGFloat = 340

    let appState: AppState
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Wallpaper")
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    choices
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            contentHeight = height
                        }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(max(contentHeight, 1), Self.maxListHeight))
                .onAppear {
                    DispatchQueue.main.async {
                        scrollToSelection(with: proxy)
                    }
                }
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 6) {
            let wallpapers = appState.library.wallpapers
            if wallpapers.isEmpty {
                Text("No wallpapers in the library yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    ForEach(wallpapers) { wallpaper in
                        ChoiceRow(
                            title: wallpaper.name,
                            detail: kindLabel(wallpaper.kind),
                            isSelected: appState.selectedWallpaperID == wallpaper.id
                        ) {
                            appState.select(wallpaper.id)
                        }
                        .id(Self.scrollID(wallpaper: wallpaper.id))
                    }
                }
            }

            let packs = appState.library.packs
            if !packs.isEmpty {
                SectionLabel(text: "Packs")
                    .padding(.top, 6)
                VStack(spacing: 1) {
                    ForEach(packs) { pack in
                        ChoiceRow(
                            title: pack.name,
                            detail: pack.summary,
                            isSelected: appState.selectedPackID == pack.id
                        ) {
                            appState.selectPack(pack.id)
                        }
                        .id(Self.scrollID(pack: pack.id))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        if let pack = appState.selectedPackID {
            proxy.scrollTo(Self.scrollID(pack: pack), anchor: .center)
        } else if let wallpaper = appState.selectedWallpaperID {
            proxy.scrollTo(Self.scrollID(wallpaper: wallpaper), anchor: .center)
        }
    }

    private static func scrollID(wallpaper id: String) -> String {
        "wallpaper:\(id)"
    }

    private static func scrollID(pack id: String) -> String {
        "pack:\(id)"
    }

    private func kindLabel(_ kind: WallpaperKind) -> String {
        switch kind {
        case .video: "Video"
        case .metal: "Shader"
        case .web: "Web"
        }
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
                Text(title)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct MusicSection: View {
    let audio: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Music")
            nowPlayingRow
            sourcePicker
            Toggle("Shuffle", isOn: Binding(get: { audio.isShuffled }, set: { audio.setShuffled($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var nowPlayingRow: some View {
        HStack(spacing: 10) {
            Button {
                audio.togglePause()
            } label: {
                Image(systemName: audio.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(audio.isPaused ? "Play" : "Pause")

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.nowPlaying?.title ?? "Nothing playing")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var detail: String {
        let source = audio.nowPlaying?.detail ?? "Pick a source below"
        guard let pause = audio.pauseDescription else { return source }
        return "\(pause) · \(source)"
    }

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(get: { audio.selection }, set: { audio.select($0) })) {
            Text("None").tag(MusicSelection.none)
            if !audio.library.playlists.isEmpty {
                Divider()
                ForEach(audio.library.playlists) { playlist in
                    Text(playlist.name).tag(MusicSelection.playlist(playlist.id))
                }
            }
            if !audio.library.streams.isEmpty {
                Divider()
                ForEach(audio.library.streams) { stream in
                    Text(stream.name).tag(MusicSelection.stream(stream.name))
                }
            }
        }
        .pickerStyle(.menu)
    }
}

private struct ProblemsSection: View {
    let problems: [Problem]

    var body: some View {
        DisclosureGroup("Problems (\(problems.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(problems) { problem in
                    Text("\(problem.location): \(problem.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
        .font(.callout)
    }
}

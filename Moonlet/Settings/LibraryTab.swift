import SwiftUI

struct LibraryTab: View {
    let appState: AppState
    let thumbnails: Thumbnails

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        let wallpapers = appState.library.wallpapers
        Group {
            if wallpapers.isEmpty {
                ContentUnavailableView(
                    "No wallpapers yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Add a folder with a wallpaper.json to the wallpapers folder in your library.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Double-click a wallpaper to show it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(wallpapers) { wallpaper in
                                WallpaperCard(
                                    wallpaper: wallpaper,
                                    isCurrent: appState.selectedWallpaperID == wallpaper.id,
                                    thumbnails: thumbnails
                                )
                                .onTapGesture(count: 2) {
                                    appState.select(wallpaper.id)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

private struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isCurrent: Bool
    let thumbnails: Thumbnails
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { preview }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isCurrent ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isCurrent ? 3 : 1)
                )

            HStack(spacing: 6) {
                Text(wallpaper.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(kindLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            Label(soundtrackText, systemImage: wallpaper.soundtrack == nil ? "speaker.slash" : "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(isCurrent ? "Showing now" : "Double-click to show")
        .task(id: wallpaper) {
            image = await thumbnails.image(for: wallpaper)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.16, blue: 0.3), Color(red: 0.24, green: 0.15, blue: 0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: wallpaper.kind == .web ? "globe" : "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var kindLabel: String {
        switch wallpaper.kind {
        case .video: "Video"
        case .metal: "Shader"
        case .web: "Web"
        }
    }

    private var soundtrackText: String {
        switch wallpaper.soundtrack {
        case .file(let url): url.lastPathComponent
        case .videoTrack: "Video's own audio"
        case nil: "No soundtrack"
        }
    }
}

import SwiftUI

struct LibraryTab: View {
    let appState: AppState
    let thumbnails: Thumbnails

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]
    @State private var isDropTargeted = false
    @State private var note: String?
    @State private var pendingDeletion: Wallpaper?
    @State private var renaming: Wallpaper?
    @State private var newName = ""

    var body: some View {
        let wallpapers = appState.library.wallpapers
        Group {
            if wallpapers.isEmpty {
                ContentUnavailableView(
                    "No wallpapers yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Drop a video, a .metal shader, or an .html page here to add it.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Double-click a wallpaper to show it, or right-click for more. Drop videos, shaders, or web pages here to add them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let note {
                            Label(note, systemImage: "tray.and.arrow.down")
                                .font(.callout)
                        }
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
                                .contextMenu {
                                    Button("Show") {
                                        appState.select(wallpaper.id)
                                    }
                                    Button("Rename…") {
                                        newName = wallpaper.name
                                        renaming = wallpaper
                                    }
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([wallpaper.folder])
                                    }
                                    Divider()
                                    Button("Move to Trash…", role: .destructive) {
                                        pendingDeletion = wallpaper
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            note = LibraryImporter.importWallpapers(urls, into: appState.library.wallpapersURL).summary
            return true
        } isTargeted: { isDropTargeted = $0 }
        .confirmationDialog(
            "Move “\(pendingDeletion?.name ?? "")” to the Trash?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { wallpaper in
            Button("Move to Trash", role: .destructive) {
                moveToTrash(wallpaper)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its folder and files go to the Trash, where you can restore them. Packs that use it will skip it.")
        }
        .alert(
            "Rename wallpaper",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { wallpaper in
            TextField("Name", text: $newName)
            Button("Rename") {
                rename(wallpaper)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This changes the name shown in Moonlet. The folder keeps its name, so packs still find it.")
        }
    }

    private func rename(_ wallpaper: Wallpaper) {
        do {
            try appState.rename(wallpaper.id, to: newName)
            note = nil
        } catch {
            note = "Could not rename \(wallpaper.name): \(error.localizedDescription)"
        }
        renaming = nil
    }

    private func moveToTrash(_ wallpaper: Wallpaper) {
        do {
            try appState.moveToTrash(wallpaper.id)
            note = "Moved \(wallpaper.name) to the Trash."
        } catch {
            note = "Could not move \(wallpaper.name) to the Trash: \(error.localizedDescription)"
        }
        pendingDeletion = nil
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

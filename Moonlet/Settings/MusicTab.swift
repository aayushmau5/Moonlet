import SwiftUI

struct MusicTab: View {
    let library: Library
    let ignoreList: IgnoreList

    @State private var targetedPlaylist: String?
    @State private var isNewPlaylistTargeted = false
    @State private var pendingAudio: [URL] = []
    @State private var newPlaylistName = ""
    @State private var isNamingPlaylist = false
    @State private var note: String?

    var body: some View {
        Form {
            playlistsSection
            streamsSection
            ignoreSection
        }
        .formStyle(.grouped)
        .alert("New playlist", isPresented: $isNamingPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                importAudio(pendingAudio, into: newPlaylistName)
                pendingAudio = []
            }
            Button("Cancel", role: .cancel) {
                pendingAudio = []
            }
        } message: {
            Text("Moonlet copies \(pendingAudio.count) audio file\(pendingAudio.count == 1 ? "" : "s") into a new playlist folder.")
        }
    }

    private var playlistsSection: some View {
        Section {
            ForEach(library.playlists) { playlist in
                HStack {
                    Label(playlist.name, systemImage: "music.note.list")
                    Spacer()
                    Text("\(playlist.tracks.count) track\(playlist.tracks.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .background(dropHighlight(targetedPlaylist == playlist.id))
                .dropDestination(for: URL.self) { urls, _ in
                    importAudio(urls, into: playlist.id)
                    return true
                } isTargeted: { isTargeted in
                    targetedPlaylist = isTargeted ? playlist.id : (targetedPlaylist == playlist.id ? nil : targetedPlaylist)
                }
            }
            Label("New playlist…", systemImage: "plus.circle")
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(dropHighlight(isNewPlaylistTargeted))
                .dropDestination(for: URL.self) { urls, _ in
                    pendingAudio = urls
                    newPlaylistName = ""
                    isNamingPlaylist = true
                    return true
                } isTargeted: { isNewPlaylistTargeted = $0 }
        } header: {
            Text("Playlists")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop audio files on a playlist to copy them in, or on New playlist to start one.")
                if let note {
                    Text(note).foregroundStyle(.primary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var streamsSection: some View {
        Section("Streams") {
            if library.streams.isEmpty {
                Text("No streams yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(library.streams) { stream in
                VStack(alignment: .leading, spacing: 2) {
                    Label(stream.name, systemImage: "antenna.radiowaves.left.and.right")
                    Text(stream.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.leading, 27)
                }
            }
            Button("Edit streams.json", action: editStreams)
        }
    }

    private var ignoreSection: some View {
        Section {
            ForEach(ignoreList.bundleIDs, id: \.self) { bundleID in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(IgnoreList.appName(for: bundleID) ?? bundleID)
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        ignoreList.remove(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                }
            }
            Menu("Add App") {
                let choices = ignoreList.runningChoices()
                if choices.isEmpty {
                    Text("No other apps are running")
                }
                ForEach(choices) { app in
                    Button(app.name) {
                        ignoreList.add(app.bundleID)
                    }
                }
            }
            .fixedSize()
        } header: {
            Text("Apps that never pause music")
        } footer: {
            Text("Moonlet keeps playing while these apps make sound.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func dropHighlight(_ isTargeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(isTargeted ? 0.18 : 0))
            .padding(-4)
    }

    private func importAudio(_ urls: [URL], into playlist: String) {
        let result = LibraryImporter.importAudio(urls, intoPlaylist: playlist, musicFolder: library.musicURL)
        note = result.summary
    }

    private func editStreams() {
        let file = library.rootURL.appending(path: StreamsFile.fileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            try? "[\n]\n".write(to: file, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(file)
    }
}

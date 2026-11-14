//
//  SearchList.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import SoundCloud

/// The active search of the toolbar search field.
/// The main view filters its elements with `query` and appends the `SearchResults` for it.
struct Search: Equatable {

    var query: String
    /// The title of the filtered main view.
    var scope: String

}

struct SearchKey: EnvironmentKey {

    static let defaultValue: Search? = nil

}

extension EnvironmentValues {

    var search: Search? {
        get { self[SearchKey.self] }
        set { self[SearchKey.self] = newValue }
    }

}

/// The header of a section shown while searching.
struct SearchSectionHeader: View {

    var title: String

    var body: some View {
        Text(title)
            .font(.title)
            .padding(.vertical, 8)
    }

}

/// Separates the sections shown while searching.
struct SearchSectionFooter: View {

    /// Set it to `false` if the section already ends with a divider.
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Spacer(minLength: 20)
                Divider()
            }
            Spacer(minLength: 20)
        }
    }

}

/// The users, tracks and playlists SoundCloud finds for `query`.
/// It doesn't scroll by itself, it is meant to be placed below the filtered main view.
struct SearchResults: View {

    var query: String

    @State private var users = [User]()
    @State private var tracks = [Track]()
    @State private var playlists = [UserPlaylist]()
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !didLoad {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
            }
            else if users.isEmpty && tracks.isEmpty && playlists.isEmpty {
                Text("No Results on SoundCloud")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            else {
                if !users.isEmpty {
                    SearchSectionHeader(title: "Users")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(users) { user in
                                DestinationLink(value: user) {
                                    UserItem(user: user)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    SearchSectionFooter()
                }
                if !tracks.isEmpty {
                    SearchSectionHeader(title: "Tracks")
                    VStack(alignment: .leading) {
                        ForEach(tracks) { track in
                            TrackRow(track: track)
                                .playbackStart(at: track)
                        }
                    }
                    .playbackContext(tracks)
                    SearchSectionFooter()
                }
                if !playlists.isEmpty {
                    SearchSectionHeader(title: "Playlists")
                    VStack(alignment: .leading) {
                        ForEach(playlists) { playlist in
                            PlaylistRow(playlist: playlist)
                        }
                    }
                    .playbackContext(playlists)
                }
            }
        }
        .task(id: query) {
            // Wait until the user stops typing to not send a request for every keystroke
            do {
                try await Task.sleep(for: .milliseconds(300))
            }
            catch {
                return
            }
            await load()
        }
    }

    private func load() async {
        let results: [Some]
        do {
            results = try await SoundCloud.shared.get(.search(query)).collection
        }
        catch {
            // The task is cancelled when the query changes or the view disappears
            guard !Task.isCancelled else { return }

            print("Failed to search for \(query): \(error)")
            results = []
        }

        users = results.compactMap { if case .user(let user) = $0 { return user } else { return nil } }
        tracks = results.compactMap { if case .track(let track) = $0 { return track } else { return nil } }
        playlists = results.compactMap { if case .userPlaylist(let playlist) = $0 { return playlist } else { return nil } }
        didLoad = true
    }

}

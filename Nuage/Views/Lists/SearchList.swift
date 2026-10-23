//
//  SearchList.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import SoundCloud

private enum SearchSection: String {
    case users
    case tracks
    case playlists
}

struct SearchList: View {
    
    var query: String
    
    @State private var users = [User]()
    @State private var tracks = [Track]()
    @State private var playlists = [UserPlaylist]()
    @State private var didLoad = false
    
    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            else if users.isEmpty && tracks.isEmpty && playlists.isEmpty {
                Text("No Results")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        if !users.isEmpty {
                            Section(content: {
                                HStack(alignment: .top) {
                                    ForEach(users) { UserItem(user: $0) }
                                }
                            }, header: header(for: .users), footer: footer)
                        }
                        if !tracks.isEmpty {
                            Section(content: {
                                VStack(alignment: .leading) {
                                    ForEach(tracks) { track in
                                        TrackRow(track: track)
                                            .playbackStart(at: track)
                                    }
                                }
                                .playbackContext(tracks)
                            }, header: header(for: .tracks), footer: footer)
                        }
                        if !playlists.isEmpty {
                            Section(content: {
                                VStack(alignment: .leading) {
                                    ForEach(playlists) { playlist in
                                        PlaylistRow(playlist: playlist)
                                    }
                                }
                                .playbackContext(playlists)
                            }, header: header(for: .playlists), footer: footer)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Search")
        .task { await load() }
    }
    
    private func load() async {
        guard !didLoad else { return }
        
        let results: [Some]
        do {
            results = try await SoundCloud.shared.get(.search(query)).collection
        }
        catch {
            // The task is cancelled when the view disappears and restarted when it reappears
            guard !Task.isCancelled else { return }
            
            print("Failed to search for \(query): \(error)")
            results = []
        }
        
        users = results.compactMap { if case .user(let user) = $0 { return user } else { return nil } }
        tracks = results.compactMap { if case .track(let track) = $0 { return track } else { return nil } }
        playlists = results.compactMap { if case .userPlaylist(let playlist) = $0 { return playlist } else { return nil } }
        didLoad = true
    }
    
    private func header(for section: SearchSection) -> () -> some View {
        @ViewBuilder func buildHeader() -> some View {
            Text(section.rawValue.capitalized)
                .font(.title)
        }
        return buildHeader
    }
    
    @ViewBuilder private func footer() -> some View {
        Spacer(minLength: 20)
        Divider()
        Spacer(minLength: 20)
    }
    
}

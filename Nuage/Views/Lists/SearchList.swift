//
//  SearchList.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import Combine
import SoundCloud

private enum SearchSection: String {
    case users
    case tracks
    case playlists
}

struct SearchList: View {
    
    var publisher: AnyPublisher<Page<Some>, Error>
    
    @State private var users = [User]()
    @State private var tracks = [Track]()
    @State private var playlists = [UserPlaylist]()
    @State private var didLoad = false
    
    @State private var subscription: AnyCancellable?
    
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
        .onAppear(perform: load)
    }
    
    private func load() {
        guard !didLoad && subscription == nil else { return }
        
        // Subscribe only once, every subscription would trigger another request
        subscription = publisher
            .map { $0.collection }
            .replaceError(with: [])
            .receive(on: RunLoop.main)
            .sink { results in
                users = results.compactMap { if case .user(let user) = $0 { return user } else { return nil } }
                tracks = results.compactMap { if case .track(let track) = $0 { return track } else { return nil } }
                playlists = results.compactMap { if case .userPlaylist(let playlist) = $0 { return playlist } else { return nil } }
                didLoad = true
            }
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

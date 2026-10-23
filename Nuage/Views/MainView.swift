//
//  MainView.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

struct MainView: View {
    
    private var soundCloud: SoundCloud { .shared }
    
    @AppStorage("sidebarSelection") private var sidebarSelection: SidebarItem = .stream
    @State private var navigationPath = NavigationPath()
    @State private var blockingNavigationPath: NavigationPath?
    
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    @Environment(MenuCommands.self) private var menuCommands
    @Environment(StreamPlayer.self) private var player
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    
    @Environment(\.showLikedPlaylists) private var showLikedPlaylists: Bool
    @Environment(\.showCreatedPlaylists) private var showCreatedPlaylists: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(sidebar: sidebar) {
                NavigationStack(path: $navigationPath) {
                    let presentSearch: Binding<Bool> = Binding(
                        get: { searchQuery.count > 0 },
                        set: { if !$0 { searchQuery = "" } }
                    )
                    
                    root(for: sidebarSelection)
                        .navigationDestinationWithPlaybackContext(for: Track.self) { TrackDetail(track: $0) }
                        .navigationDestination(for: User.self) { UserDetail(user: $0) }
                        .navigationDestination(for: URL.self) { URLDetail(url: $0) }
                        .navigationDestination(for: AnyPlaylist.self) { playlist in
                            TrackList(playlist: playlist)
                                .navigationTitle(playlist.title)
                        }
                        .navigationDestination(for: Station.self) { station in
                            switch station {
                            case .track(let track): TrackList(request: .trackStation(basedOn: track))
                            case .artist(let user): TrackList(request: .artistStation(basedOn: user))
                            }
                        }
                        .navigationDestination(isPresented: presentSearch) {
                            SearchList(query: searchQuery)
                                .id(searchQuery)
                        }
                }
            }
            if player.queue.count > 0 {
                Divider()
                PlayerView {
                    if let track = player.currentStream, navigationPath != blockingNavigationPath {
                        navigationPath.append(track, with: player.queue, startPlaybackAt: track, player: player)
                        blockingNavigationPath = navigationPath
                    }
                }
            }
        }
        .toolbarRole(.editor)
        .toolbar(content: toolbar)
        .searchable(text: $searchQuery, placement: .toolbar)
        .searchFocused($isSearchFocused)
        .onChange(of: menuCommands.searchRequests) { isSearchFocused = true }
        .touchBar { TouchBar() }
        .onChange(of: sidebarSelection) {
            navigationPath = NavigationPath()
            blockingNavigationPath = nil
        }
        .onOpenURL { url in
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
            
            components.scheme = "https"
            guard let newURL = components.url else { return }
            navigationPath.append(newURL)
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
    
    @ViewBuilder private func sidebar() -> some View {
        List(selection: $sidebarSelection) {
            sidebarMenu(for: .discover)
            sidebarMenu(for: .stream)
            sidebarMenu(for: .likes)
            sidebarMenu(for: .history)
            sidebarMenu(for: .following)
            
            if (showLikedPlaylists || showCreatedPlaylists) && !playlists.isEmpty {
                Section(header: Text("Playlists")) {
                    ForEach(playlists) { playlist in
                        let isLiked = (playlist.userPlaylist?.secretToken == nil)
                        
                        if (isLiked && showLikedPlaylists) || (!isLiked && showCreatedPlaylists) {
                            if let playlist = playlist.userPlaylist {
                                sidebarMenu(for: .userPlaylist(playlist.title, playlist.id))
                            }
                            else if let playlist = playlist.systemPlaylist {
                                sidebarMenu(for: .systemPlaylist(playlist.title, playlist.id))
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder private func sidebarMenu(for detail: SidebarItem) -> some View {
        NavigationLink(value: detail) {
            HStack {
                if let imageName = detail.imageName {
                    Image(systemName: imageName)
                        .frame(width: 20, alignment: .center)
                }
                Text(detail.title)
            }
        }
    }
    
    @ViewBuilder private func root(for item: SidebarItem) -> some View {
        Group {
            switch item {
            case .discover:
                DiscoverView()
            case .stream:
                PostList(for: { try await SoundCloud.shared.get(.stream(), count: 50) })
            case .likes:
                // The user is loaded after logging in
                if let user = soundCloud.user {
                    TrackList(for: { try await SoundCloud.shared.get(.trackLikes(of: user), count: 50) })
                }
                else {
                    loadingIndicator()
                }
            case .history:
                TrackList(for: { try await SoundCloud.shared.get(.history(), count: 50) })
            case .following:
                if let user = soundCloud.user {
                    UserGrid(for: { try await SoundCloud.shared.get(.followings(of: user), count: 50) })
                }
                else {
                    loadingIndicator()
                }
            case .userPlaylist(_, let id):
                TrackList(request: .userPlaylist(id))
            case .systemPlaylist(_, let urn):
                TrackList(request: .systemPlaylist(urn))
            }
        }
            .navigationTitle(item.title)
            .id(item.id) // Set id so that SwiftUI knows when to render new view
    }
    
    @ViewBuilder private func loadingIndicator() -> some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ToolbarContentBuilder private func toolbar() -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                if let user = soundCloud.user {
                    navigationPath.append(user)
                }
            } label: {
                RemoteImage(url: soundCloud.user?.avatarURL, cornerRadius: 15)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }
    
}

struct MainView_Previews: PreviewProvider {
    
    static var previews: some View {
        let player: StreamPlayer = {
            let player = StreamPlayer()
            player.enqueue(Preview.tracks)
            return player
        }()
        
        MainView()
            .environment(player)
            .environment(MenuCommands())
    }
    
}

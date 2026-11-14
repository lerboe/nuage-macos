//
//  MainView.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import AppKit
import SoundCloud

struct MainView: View {
    
    private var soundCloud: SoundCloud { .shared }
    
    @AppStorage("sidebarSelection") private var sidebarSelection: SidebarItem = .stream
    @State private var navigationPath = NavigationPath()
    @State private var blockingNavigationPath: NavigationPath?
    
    @State private var searchQuery = ""

    @Environment(MenuCommands.self) private var menuCommands
    @Environment(StreamPlayer.self) private var player
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    
    @Environment(\.showLikedPlaylists) private var showLikedPlaylists: Bool
    @Environment(\.showCreatedPlaylists) private var showCreatedPlaylists: Bool
    
    private var isPlayerVisible: Bool { player.queue.count > 0 }
    
    private var search: Search? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : Search(query: query, scope: sidebarSelection.title)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(sidebar: sidebar) {
                NavigationStack(path: $navigationPath) {
                    root(for: sidebarSelection)
                        .navigationDestinationWithPlaybackContext(for: Track.self) { TrackDetail(track: $0) }
                        .navigationDestination(for: User.self) { UserDetail(user: $0) }
                        .navigationDestination(for: URL.self) { URLDetail(url: $0) }
                        .navigationDestination(for: AnyPlaylist.self) { playlist in
                            TrackList(playlist: playlist)
                                .navigationTitle(playlist.title)
                                .toolbar { ProfileToolbarItem() }
                                .presenting(playlist)
                        }
                        .navigationDestination(for: Station.self) { station in
                            Group {
                                switch station {
                                case .track(let track): TrackList(request: .trackStation(basedOn: track))
                                case .artist(let user): TrackList(request: .artistStation(basedOn: user))
                                }
                            }
                            .toolbar { ProfileToolbarItem() }
                            .presenting(station)
                        }
                }
            }
            if isPlayerVisible {
                VStack(spacing: 0) {
                    Divider()
                    PlayerView {
                        if let track = player.currentStream, navigationPath != blockingNavigationPath {
                            navigationPath.append(track, with: player.queue, startPlaybackAt: track, player: player)
                            blockingNavigationPath = navigationPath
                        }
                    }
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.35), value: isPlayerVisible)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarSearchField(text: $searchQuery, focusRequests: menuCommands.searchRequests)
                    .frame(width: 250)
            }
        }
        .onChange(of: search == nil) {
            // Searching shows the filtered main view, so go back to it when a search starts
            if search != nil {
                navigationPath = NavigationPath()
                blockingNavigationPath = nil
            }
        }
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
        .toolbar(removing: .sidebarToggle)
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
            .toolbar { ProfileToolbarItem() }
            // Only the main view is filtered, not the views pushed onto it
            .environment(\.search, search)
            .id(item.id) // Set id so that SwiftUI knows when to render new view
    }
    
    @ViewBuilder private func loadingIndicator() -> some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
}

/// Shows the logged in user's avatar and opens their profile.
/// Toolbar items of a parent view are placed before the ones of its children,
/// so every view in the navigation stack adds this item last to keep it the trailing-most element.
struct ProfileToolbarItem: ToolbarContent {
    
    private var soundCloud: SoundCloud { .shared }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let user = soundCloud.user {
                DestinationLink(value: user) {
                    RemoteImage(url: user.avatarURL, cornerRadius: 15)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
    
}

/// A search field with a fixed width, unlike the one of `searchable(text:placement:prompt:)`,
/// which is drawn wider than the toolbar item laid out for it.
private struct ToolbarSearchField: NSViewRepresentable {
    
    @Binding var text: String
    /// Focuses the field whenever it changes.
    var focusRequests: Int
    
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "Search")
        // Sent while typing and when the field is cleared
        field.target = context.coordinator
        field.action = #selector(Coordinator.textDidChange(_:))
        field.delegate = context.coordinator
        return field
    }
    
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if focusRequests != context.coordinator.focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.window?.makeFirstResponder(field)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        
        var parent: ToolbarSearchField
        var focusRequests: Int
        
        init(parent: ToolbarSearchField) {
            self.parent = parent
            self.focusRequests = parent.focusRequests
        }
        
        @objc func textDidChange(_ field: NSSearchField) {
            parent.text = field.stringValue
        }
        
        /// Escape clears the field and ends editing, like the field of `searchable(text:placement:prompt:)`.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            
            control.stringValue = ""
            parent.text = ""
            control.window?.makeFirstResponder(nil)
            return true
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

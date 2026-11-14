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
    @FocusState private var isSearchFocused: Bool

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
                        }
                        .navigationDestination(for: Station.self) { station in
                            Group {
                                switch station {
                                case .track(let track): TrackList(request: .trackStation(basedOn: track))
                                case .artist(let user): TrackList(request: .artistStation(basedOn: user))
                                }
                            }
                            .toolbar { ProfileToolbarItem() }
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
        .searchable(text: $searchQuery, placement: .toolbarPrincipal)
        .searchFocused($isSearchFocused)
        .focusesToolbarSearchFieldOnClick(focus: { isSearchFocused = true }, clear: { searchQuery = "" })
        .onChange(of: menuCommands.searchRequests) { isSearchFocused = true }
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
                NavigationLink(value: user) {
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

/// Works around the principal toolbar item being laid out narrower than the search field it draws.
/// Only clicks within the item's frame reach the field, so clicks on the outer parts of the field
/// are caught here and focus the field manually, or clear it if they hit the clear button.
private struct ToolbarSearchFieldClickFocus: ViewModifier {
    
    var focus: () -> Void
    var clear: () -> Void
    @State private var monitor: Any?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    handle(event) ? nil : event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }
    
    /// Returns whether the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // The toolbar lives in the window's frame view, the superview of the content view
        guard let window = event.window,
              let frameView = window.contentView?.superview,
              let searchField = frameView.firstDescendant(ofType: NSSearchField.self),
              !searchField.isHiddenOrHasHiddenAncestor else { return false }
        
        let location = searchField.convert(event.locationInWindow, from: nil)
        guard searchField.bounds.contains(location) else { return false }
        
        // Clicks that already reach the field are handled by AppKit
        if let hitView = frameView.hitTest(event.locationInWindow), hitView.isDescendant(of: searchField) {
            return false
        }
        
        if !searchField.stringValue.isEmpty,
           let cell = searchField.cell as? NSSearchFieldCell,
           cell.cancelButtonRect(forBounds: searchField.bounds).contains(location) {
            clear()
        }
        else {
            focus()
        }
        return true
    }
    
}

private extension NSView {
    
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
    
}

private extension View {
    
    func focusesToolbarSearchFieldOnClick(focus: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        modifier(ToolbarSearchFieldClickFocus(focus: focus, clear: clear))
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

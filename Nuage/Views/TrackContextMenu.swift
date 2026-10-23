//
//  TrackContextMenu.swift
//  Nuage
//
//  Created by Laurin Brandner on 04.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

private struct TrackContextMenu: ViewModifier {
    
    private var soundCloud: SoundCloud { .shared }
    
    var track: Track
    
    @Environment(StreamPlayer.self) private var player
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLike: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepost: (Track) -> () -> ()
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Play", action: onPlay)
            Button("Add to Queue") {
                player.enqueue([track])
            }
            Divider()
            Button(likes.contains(track) ? "Unlike" : "Like", action: toggleLike(track))
            Button(posts.isReposted(track) ? "Remove Repost" : "Repost", action: toggleRepost(track))
            
            let playlists = playlists
                .compactMap { $0.userPlaylist }
                .filter { $0.secretToken != nil }
            if let newTrackID = Int(track.id), playlists.count > 0 {
                Menu("Add to Playlist") {
                    ForEach(playlists, id: \.id) { playlist in
                        Button(playlist.title) {
                            add(trackID: newTrackID, to: playlist)
                        }
                    }
                }
            }
            Divider()
            Button("Copy Link") {
                let text = track.permalinkURL.absoluteString
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
    
    private func add(trackID: Int, to playlist: UserPlaylist) {
        // Not tied to the view, the request should finish even if the menu's view disappears
        Task {
            do {
                // Load the playlist first, since the cached one might be outdated
                let current = try await soundCloud.get(.userPlaylist(playlist.id))
                let trackIDs = (current.trackIDs ?? []).compactMap { Int($0) }
                _ = try await soundCloud.get(.set(playlist, trackIDs: trackIDs + [trackID]))
            }
            catch {
                print("Failed to add track to playlist: \(error)")
            }
        }
    }

}

extension View {
    
    func trackContextMenu(with track: Track) -> some View {
        return modifier(TrackContextMenu(track: track))
    }
    
}

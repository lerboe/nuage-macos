//
//  FeedbackStack.swift
//  Nuage
//
//  Created by Laurin Brandner on 24.07.23.
//

import SwiftUI
import SoundCloud

struct FeedbackStack<T: SoundCloudIdentifiable>: View {
    
    private var item: T?
    private var horizontal: Bool
    
    private var isLiked: Bool {
        if let track = item as? Track {
            return likes.contains(track)
        }
        else if let playlist = item as? (any Playlist) {
            return playlists.contains(playlist.eraseToAnyPlaylist())
        }
        else {
            return false
        }
    }
    
    private var isRepost: Bool? {
        if let track = item as? Track {
            return posts.isReposted(track)
        }
        else if let playlist = item as? (any Playlist) {
            // Only user playlists can be reposted
            guard let playlist = playlist as? UserPlaylist else {
                return nil
            }
            return posts.isReposted(playlist)
        }
        else {
            return false
        }
    }
    
    private var toggleLike: () -> () {
        if let track = item as? Track {
            return toggleLikeTrack(track)
        }
        else if let playlist = item as? (any Playlist) {
            return toggleLikePlaylist(playlist.eraseToAnyPlaylist())
        }
        else {
            return {}
        }
    }
    
    private var toggleRepost: () -> () {
        if let track = item as? Track {
            return toggleRepostTrack(track)
        }
        else if let playlist = item as? UserPlaylist {
            return toggleRepostPlaylist(playlist)
        }
        else {
            return {}
        }
    }
    
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.posts) private var posts: [Post]
    
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    @Environment(\.toggleLikePlaylist) private var toggleLikePlaylist: (AnyPlaylist) -> () -> ()
    @Environment(\.toggleRepostPlaylist) private var toggleRepostPlaylist: (UserPlaylist) -> () -> ()
    
    var body: some View {
        if horizontal {
            HStack(content: content)
        }
        else {
            VStack(content: content)
        }
    }
    
    @ViewBuilder private func content() -> some View {
        Button(action: toggleLike) {
            let name = isLiked ? "heart.fill" : "heart"
            Image(systemName: name)
        }
        .disabled(item == nil)
        .buttonStyle(.borderless)

        if let isRepost = isRepost {
            Button(action: toggleRepost) {
                let name = isRepost ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle"
                Image(systemName: name)
            }
            .disabled(item == nil)
            .buttonStyle(.borderless)
        }
    }
    
    init(for playlist: T, horizontal: Bool = true) where T: Playlist {
        self.item = playlist
        self.horizontal = horizontal
    }
    
    init(for track: T?, horizontal: Bool = true) where T == Track {
        self.item = track
        self.horizontal = horizontal
    }
    
}

//
//  TrackContextMenu.swift
//  Nuage
//
//  Created by Laurin Brandner on 04.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import Combine
import SoundCloud

private struct TrackContextMenu: ViewModifier {
    
    @ObservedObject private var soundCloud = SoundCloud.shared
    
    var track: Track
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    @EnvironmentObject private var player: StreamPlayer
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
        soundCloud.get(.userPlaylist(playlist.id))
            .map { ($0.trackIDs ?? []).compactMap { Int($0) } }
            .flatMap { soundCloud.get(.set(playlist, trackIDs: $0 + [trackID])) }
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to add track to playlist: \(error)")
                }
            }, receiveValue: { _ in })
            .store(in: &subscriptions)
    }

}

extension View {
    
    func trackContextMenu(with track: Track) -> some View {
        return modifier(TrackContextMenu(track: track))
    }
    
}

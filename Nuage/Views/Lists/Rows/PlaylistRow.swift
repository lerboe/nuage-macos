//
//  PlaylistRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import SoundCloud

struct PlaylistRow<T: Playlist>: View {
    
    var playlist: T
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    var body: some View {
        let artworkURL = playlist.artworkURL ?? playlist.tracks?.first?.artworkURL
        
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading) {
                Artwork(url: artworkURL, onPlay: onPlay)
                    .frame(width: 100, height: 100)
                FeedbackStack(for: playlist)
            }
            .padding(.bottom, 16)
            
            VStack(alignment: .leading) {
                Text(playlist.title)
                    .font(.title3)
                    .bold()
                    .lineLimit(1)
                DestinationLink(playlist.user.username, value: playlist.user)
                    .buttonStyle(.plain)
                Spacer()
                    .frame(height: 8)

                if let description = playlist.description {
                    let text = description
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .withAttributedLinks()
                    
                    Text(text).lineLimit(3)
                }
                
                if let tracks = playlist.tracks {
                    ForEach(tracks) { track in
                        Divider()
                        HStack {
                            Text(track.title)
                            StatsStack(for: track)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                    .frame(height: 8)
            }
        }
    }

}

//
//  TrackRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import SoundCloud

struct TrackRow: View {
    
    var track: Track
    
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    var body: some View {
        let duration = format(time: track.duration)
        
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading) {
                Artwork(url: track.artworkURL ?? track.user.avatarURL, onPlay: onPlay)
                    .frame(width: 100, height: 100)
                FeedbackStack(for: track)
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading) {
                PlaybackNavigationLink(value: track) {
                    Text(track.title)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                NavigationLink(track.user.username, value: track.user)
                    .buttonStyle(.plain)
                
                StatsStack(for: track)
                    .foregroundColor(.secondary)
                Text(duration)
                    .foregroundColor(.secondary)
                
                Spacer()
                    .frame(height: 8)

                if let description = track.description {
                    let text = description
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .withAttributedLinks()
                        
                    Text(text)
                        .lineLimit(3)
                }
            }
        }
    }

}

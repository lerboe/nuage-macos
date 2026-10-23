//
//  TrackDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 18.11.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

struct TrackDetail: View {
    
    var track: Track
    
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    var body: some View {
        let duration = format(time: track.duration)
        let url = track.artworkURL ?? track.user.avatarURL
        
        VStack(alignment: .leading) {
            Text(track.title)
                .font(.title)
                .lineLimit(2)
            
            Spacer()
                .frame(height: 2)
            
            HStack {
                NavigationLink(value: track.user) {
                    Text(track.user.username)
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Spacer()
                    .frame(width: 16)
                
                StatsStack(for: track)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .center, spacing: 10) {
                Artwork(url: url, onPlay: onPlay)
                    .frame(width: 100, height: 100)
                
                WaveformView(url: track.waveformURL)
                    .foregroundColor(.secondary)
                    .frame(height: 80)
            }
            
            FeedbackStack(for: track)
            
            Text(duration)
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            Spacer()
                .frame(height: 8)
            
            Divider()
            
            CommentList(for: SoundCloud.shared.get(.comments(of: track)))
                .header {
                    if let description = track.description {
                        Text(description.withAttributedLinks())
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink(value: Station.track(track)) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            }
        }
        .padding(16)
        .navigationTitle(track.title)
    }
    
}

struct TrackDetail_Previews: PreviewProvider {
    
    static var previews: some View {
        let player: StreamPlayer = {
            let player = StreamPlayer()
            player.enqueue(Preview.tracks)
            
            return player
        }()
        
        TrackDetail(track: Preview.tracks.first!)
            .environmentObject(player)
            .environmentObject(CommandSubject())
    }
    
}

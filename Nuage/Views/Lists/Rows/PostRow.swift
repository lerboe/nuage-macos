//
//  PostRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.07.23.
//

import SwiftUI
import SoundCloud

struct PostRow: View {
    
    var post: Post
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 10) {
                NavigationLink(value: post.user) {
                    RemoteImage(url: post.user.avatarURL, cornerRadius: 15)
                        .frame(width: 30, height: 30)
                    
                    let title: AttributedString = {
                        var attributes = AttributeContainer()
                        attributes.font = .body.bold()
                        attributes.foregroundColor = .primary
                        let username = AttributedString(post.user.username, attributes: attributes)
                        
                        let action = post.isRepost ? " reposted" : " posted"
                        attributes = AttributeContainer()
                        attributes.foregroundColor = .secondary
                        return username + AttributedString(action, attributes: attributes)
                    }()
                    
                    Text(title)
                }
                .buttonStyle(.plain)
            }
            Spacer()
                .frame(height: 18)
            
            if case let .track(track) = post.item {
                TrackRow(track: track)
                    .trackContextMenu(with: track)
            }
            else if case let .playlist(playlist) = post.item {
                PlaylistRow(playlist: playlist)
            }
        }
    }
    
}


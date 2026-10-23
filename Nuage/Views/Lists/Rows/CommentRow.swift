//
//  CommentRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 19.02.21.
//

import SwiftUI
import SoundCloud

struct CommentRow: View {
    
    var comment: Comment
    
    var body: some View {
        HStack {
            NavigationLink(value: comment.user) {
                RemoteImage(url: comment.user.avatarURL, cornerRadius: 25)
                    .frame(width: 50, height: 50, alignment: .center)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading) {
                let time = format(time: comment.timestamp)
                Text("\(comment.user.username) at \(time)")
                    .bold()
                Text(comment.body)
            }
        }
        .padding(6)
    }

}

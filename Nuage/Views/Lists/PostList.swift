//
//  PostList.swift
//  Nuage
//
//  Created by Laurin Brandner on 20.12.20.
//

import SwiftUI
import Combine
import SoundCloud

struct PostList: View {
    
    private var publisher: InfinitePublisher<Post>
    
    var body: some View {
        InfiniteList(publisher: publisher) { post in
            PostRow(post: post)
                .playbackStart(at: post)
        }
    }
    
    init(for publisher: AnyPublisher<Page<Post>, Error>) {
        self.publisher = .page(publisher)
    }

}

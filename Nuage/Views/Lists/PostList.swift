//
//  PostList.swift
//  Nuage
//
//  Created by Laurin Brandner on 20.12.20.
//

import SwiftUI
import SoundCloud

struct PostList: View {
    
    private var source: InfiniteSource<Post>
    
    var body: some View {
        InfiniteList(source: source) { post in
            PostRow(post: post)
                .playbackStart(at: post)
        }
    }
    
    init(for firstPage: @escaping () async throws -> Page<Post>) {
        self.source = .page(firstPage)
    }

}

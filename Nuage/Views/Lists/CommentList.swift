//
//  CommentList.swift
//  Nuage
//
//  Created by Laurin Brandner on 19.02.21.
//

import SwiftUI
import Combine
import SoundCloud

struct CommentList: View {
    
    var publisher: InfinitePublisher<Comment>
    
    var body: some View {
        InfiniteList(publisher: publisher) { comment in
            CommentRow(comment: comment)
        }
    }
    
    init(for publisher: AnyPublisher<Page<Comment>, Error>) {
        self.publisher = .page(publisher)
    }
    
}

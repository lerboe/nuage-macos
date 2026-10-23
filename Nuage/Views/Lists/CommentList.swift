//
//  CommentList.swift
//  Nuage
//
//  Created by Laurin Brandner on 19.02.21.
//

import SwiftUI
import SoundCloud

struct CommentList: View {
    
    var source: InfiniteSource<Comment>
    
    var body: some View {
        InfiniteList(source: source) { comment in
            CommentRow(comment: comment)
        }
    }
    
    init(for firstPage: @escaping () async throws -> Page<Comment>) {
        self.source = .page(firstPage)
    }
    
}

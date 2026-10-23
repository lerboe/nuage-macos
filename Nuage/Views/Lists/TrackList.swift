//
//  TrackList.swift
//  Nuage
//
//  Created by Laurin Brandner on 23.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

struct TrackList<Element: Decodable&SoundCloudIdentifiable&Filterable&Hashable>: View {
    
    private var source: InfiniteSource<Element>
    private var transform: (Element) -> Track
    
    var body: some View {
        InfiniteList(source: source) { elem in
            let track = transform(elem)
            TrackRow(track: track)
                .playbackStart(at: elem) { [transform($0)] }
                .trackContextMenu(with: track)
        }
    }
    
}

extension TrackList where Element == Track {
    
    init(for firstPage: @escaping () async throws -> Page<Track>) {
        self.init(source: .page(firstPage)) { $0 }
    }
    
    /// Loads the tracks with the ids returned by `loadIDs` in batches.
    init(ids loadIDs: @escaping () async throws -> [String]) {
        let loadTracks = { (ids: [String]) in
            try await SoundCloud.shared.get(.tracks(ids))
        }
        self.init(source: .array(loadIDs, loadTracks), transform: { $0 })
    }
    
    init<P: Playlist>(request: APIRequest<P>) {
        self.init(ids: { try await SoundCloud.shared.get(request).trackIDs ?? [] })
    }

    init(playlist: AnyPlaylist) {
        if let ids = playlist.trackIDs, !ids.isEmpty {
            self.init(ids: { ids })
            return
        }
        switch playlist {
        case .user(let p): self.init(request: .userPlaylist(p.id))
        case .system(let p): self.init(request: .systemPlaylist(p.urn))
        }
    }

}

extension TrackList where Element == Like<Track> {
    
    init(for firstPage: @escaping () async throws -> Page<Like<Track>>) {
        self.init(source: .page(firstPage)) { $0.item }
    }
    
}

extension TrackList where Element == HistoryItem {
    
    init(for firstPage: @escaping () async throws -> Page<HistoryItem>) {
        self.init(source: .page(firstPage)) { $0.track }
    }
    
}

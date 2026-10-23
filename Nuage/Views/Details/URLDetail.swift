//
//  URLDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 02.08.23.
//

import SwiftUI
import SoundCloud

struct URLDetail: View {
    
    var url: URL
    @State private var item: Some?
    @State private var didFail = false
    
    var body: some View {
        switch item {
        case nil where didFail:
            Text("Could not open \(url.absoluteString)")
                .font(.title2)
                .foregroundColor(.secondary)
        case nil: loadingIndicator()
        case .track(let track): TrackDetail(track: track)
                .playbackContext([track])
                .playbackStart(at: track)
        case .user(let user): UserDetail(user: user)
        case .userPlaylist(let playlist): TrackList(request: .userPlaylist(playlist.id))
        case .systemPlaylist(let playlist): TrackList(request: .systemPlaylist(playlist.urn))
        }
    }
    
    @ViewBuilder private func loadingIndicator() -> some View {
        ProgressView()
            .progressViewStyle(.circular)
            .task {
                do {
                    item = try await SoundCloud.shared.get(.resolve(url))
                }
                catch {
                    guard !Task.isCancelled else { return }
                    
                    print("Failed to resolve \(url): \(error)")
                    didFail = true
                }
            }
    }
    
}

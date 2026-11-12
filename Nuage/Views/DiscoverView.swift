//
//  DiscoverView.swift
//  Nuage
//

import SwiftUI
import SoundCloud

struct DiscoverView: View {

    @State private var selections = [Selection]()
    @State private var didLoad = false

    @Environment(\.search) private var search: Search?

    var body: some View {
        Group {
            if selections.isEmpty && !didLoad {
                ProgressView().progressViewStyle(.circular)
            } else {
                let displayedSelections = search.map { search in
                    selections.compactMap { $0.filtered(by: search.query) }
                } ?? selections

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // The section of the main view is left out if nothing in it matches
                        if let search, !displayedSelections.isEmpty {
                            SearchSectionHeader(title: search.scope)
                        }
                        ForEach(displayedSelections) { selection in
                            SelectionRow(selection: selection)
                        }
                        if let search {
                            VStack(alignment: .leading, spacing: 0) {
                                if !displayedSelections.isEmpty {
                                    SearchSectionFooter()
                                }
                                SearchResults(query: search.query)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !didLoad else { return }

        do {
            selections = try await SoundCloud.shared.get(.mixedSelections(), limit: 10).collection
        }
        catch {
            // The task is cancelled when the view disappears and restarted when it reappears
            guard !Task.isCancelled else { return }
            print("Failed to load selections: \(error)")
        }
        didLoad = true
    }

}

private struct SelectionRow: View {

    var selection: Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selection.title)
                .font(.title2)
                .bold()
            if let description = selection.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(selection.items.uniqued(), id: \.uniqueID) { item in
                        switch item {
                        case .playlist(let playlist): PlaylistCard(playlist: playlist)
                        case .user(let user): UserCard(user: user)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

}

private let cardWidth: CGFloat = 160

private struct PlaylistCard: View {

    var playlist: AnyPlaylist

    var body: some View {
        NavigationLink(value: playlist) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: playlist.artworkURL, cornerRadius: 6)
                    .frame(width: cardWidth, height: cardWidth)
                Text(playlist.title)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if playlist.userPlaylist != nil {
                    Text(playlist.user.username)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

}

private struct UserCard: View {

    var user: User

    var body: some View {
        NavigationLink(value: user) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: user.avatarURL, cornerRadius: cardWidth / 2)
                    .frame(width: cardWidth, height: cardWidth)
                Text(user.username)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let followers = user.followerCount {
                    HStack(spacing: 2) {
                        Text(format(count: followers))
                        Image(systemName: "person.2.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

}

private extension AnyItem {

    // `id` collapses User and Playlist IDs into the same numeric namespace.
    // Prefix by kind so the dedupe and ForEach identity stay correct.
    var uniqueID: String {
        switch self {
        case .user(let user): return "user:\(user.id)"
        case .playlist(let playlist): return "playlist:\(playlist.id)"
        }
    }

}

private extension AnyItem {

    func contains(_ text: String) -> Bool {
        switch self {
        case .user(let user): return user.contains(text)
        case .playlist(let playlist):
            return playlist.userPlaylist?.contains(text) ?? playlist.systemPlaylist?.contains(text) ?? false
        }
    }

}

private extension Selection {

    /// The selection with only the items containing `text`, or `nil` if none does.
    func filtered(by text: String) -> Selection? {
        var selection = self
        selection.items = items.filter { $0.contains(text) }
        return selection.items.isEmpty ? nil : selection
    }

}

private extension Array where Element == AnyItem {

    // The endpoint can repeat the same item in a row (e.g. "Recently Played"
    // returns the same mix once per play). Keep the first occurrence.
    func uniqued() -> [AnyItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.uniqueID).inserted }
    }

}

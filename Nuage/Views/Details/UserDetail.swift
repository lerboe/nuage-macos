//
//  UserDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 03.01.21.
//

import SwiftUI
import SoundCloud

struct UserDetail: View {
    
    var user: User
    @State private var loadedUser: User?
    @State private var selection: Tab = .stream
    /// Whether the user's station could be loaded, SoundCloud has none for some users, e.g. ones without tracks.
    @State private var hasStation = false
    
    var body: some View {
        let currentUser = loadedUser ?? user
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                RemoteImage(url: currentUser.avatarURL, cornerRadius: 50)
                    .frame(width: 100, height: 100)
                
                VStack(alignment: .leading) {
                    Text(user.username)
                        .font(.title)
                        .lineLimit(1)
                    
                    HStack {
                        Text("\(format(count: currentUser.followerCount ?? 0)) Followers")
                        Text("\(format(count: currentUser.followingCount ?? 0)) Following")
                    }
                    
                    if let description = currentUser.description {
                        Text(description.withAttributedLinks())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            
            HStack(spacing: 40) {
                button(for: .stream)
                button(for: .likes)
                button(for: .following)
                button(for: .followers)
            }
            .buttonStyle(.plain)
            
            Divider()
                .padding(.top, 8)

            stream(for: selection)
                // Following and followers share the same view type, force a new one to reset its state
                .id(selection)
        }
        .toolbar {
            // Placed right after the search field. The item stays in place, since toolbar items
            // added after the view appeared don't show up.
            ToolbarItem(placement: .secondaryAction) {
                if hasStation {
                    DestinationLink(value: Station.artist(user)) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
            }
            ProfileToolbarItem()
        }
        .navigationTitle(user.username)
        .presenting(user)
        .task {
            guard !hasStation else { return }
            hasStation = (try? await SoundCloud.shared.get(.artistStation(basedOn: user))) != nil
        }
        .task {
            guard loadedUser == nil else { return }
            
            do {
                loadedUser = try await SoundCloud.shared.get(.user(with: user.id))
            }
            catch {
                guard !Task.isCancelled else { return }
                print("Failed to load user: \(error)")
            }
        }
    }
    
    @ViewBuilder private func button(for tab: Tab) -> some View {
        Button(action: { selection = tab }, label: {
            let color: Color = selection == tab ? .primary : .secondary
            
            Text(tab.rawValue.capitalized)
                .font(.title2)
                .foregroundColor(color)
        })
    }
    
    @ViewBuilder private func stream(for selection: Tab) -> some View {
        switch selection {
        case .stream: PostList(for: { try await SoundCloud.shared.get(.stream(of: user)) })
        case .likes: TrackList(for: { try await SoundCloud.shared.get(.trackLikes(of: user)) })
        case .following: UserGrid(for: { try await SoundCloud.shared.get(.followings(of: user)) })
        case .followers: UserGrid(for: { try await SoundCloud.shared.get(.followers(of: user)) })
        }
    }
    
}

extension UserDetail {
    
    enum Tab: String {
        case stream
        case likes
        case following
        case followers
    }
    
}

struct UserDetail_Previews: PreviewProvider {
    
    static var previews: some View {
        UserDetail(user: Preview.tracks.first!.user)
            .environment(StreamPlayer())
            .environment(MenuCommands())
    }
    
}


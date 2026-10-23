//
//  Library.swift
//  Nuage
//
//  Created by Laurin Brandner on 23.10.26.
//

import Foundation
import Combine
import SoundCloud

private let userKey = "user"

/// Holds the logged in user's playlists, likes and posts and performs the actions modifying them.
class Library: ObservableObject {

    @Published private(set) var playlists = [AnyPlaylist]()
    @Published private(set) var likes = [Track]()
    @Published private(set) var posts = [Post]()

    private var subscriptions = Set<AnyCancellable>()
    private var playlistsSubscription: AnyCancellable?
    private var likesSubscription: AnyCancellable?
    private var postsSubscription: AnyCancellable?
    private var actionSubscriptions = [UUID: AnyCancellable]()

    init() {
        // Persist the user so that it's available right away on the next launch
        SoundCloud.shared.$user
            .dropFirst()
            .sink { user in
                let defaults = UserDefaults.standard
                if let user = user, let data = try? JSONEncoder().encode(user) {
                    defaults.set(data, forKey: userKey)
                }
                else {
                    defaults.removeObject(forKey: userKey)
                }
            }
            .store(in: &subscriptions)

        SoundCloud.shared.$user
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                guard SoundCloud.shared.accessToken != nil else { return }
                self?.reloadPlaylists()
                self?.reloadLikes(of: user)
                self?.reloadPosts(of: user)
            }
            .store(in: &subscriptions)
    }

    static func restoreUser() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: userKey) else { return }

        do {
            SoundCloud.shared.user = try JSONDecoder().decode(User.self, from: data)
        }
        catch {
            defaults.removeObject(forKey: userKey)
            print("Failed to load user from UserDefaults: \(error)")
        }
    }

    static func forgetUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }
    
    // MARK: - Loading

    private func reloadPlaylists() {
        playlistsSubscription = SoundCloud.shared.get(all: .library())
            .map { $0.map { $0.item } }
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to load playlists: \(error)")
                }
            }, receiveValue: { [weak self] playlists in
                self?.playlists = playlists
            })
    }

    private func reloadLikes(of user: User) {
        likesSubscription = SoundCloud.shared.get(all: .trackLikes(of: user))
            .map { $0.map { $0.item } }
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to load likes: \(error)")
                }
            }, receiveValue: { [weak self] likes in
                self?.likes = likes
            })
    }

    private func reloadPosts(of user: User) {
        postsSubscription = SoundCloud.shared.get(all: .stream(of: user))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to load posts: \(error)")
                }
            }, receiveValue: { [weak self] posts in
                self?.posts = posts
            })
    }

    private func reloadPosts() {
        guard let user = SoundCloud.shared.user else { return }
        reloadPosts(of: user)
    }

    // MARK: - State

    func isLiked(_ track: Track) -> Bool {
        return likes.contains(track)
    }

    func isLiked(_ playlist: AnyPlaylist) -> Bool {
        return playlists.contains(playlist)
    }

    func isReposted(_ track: Track) -> Bool {
        return posts.isReposted(track)
    }

    func isReposted(_ playlist: UserPlaylist) -> Bool {
        return posts.isReposted(playlist)
    }

    // MARK: - Actions

    func toggleLike(_ track: Track) {
        let shouldUnlike = isLiked(track)
        let request: APIRequest = shouldUnlike ? .unlike(track) : .like(track)

        perform(request, description: "like track") { [weak self] in
            guard let self = self else { return }
            if shouldUnlike {
                self.likes.removeAll { $0 == track }
            }
            else if !self.likes.contains(track) {
                self.likes.insert(track, at: 0)
            }
        }
    }

    func toggleLike(_ playlist: AnyPlaylist) {
        let shouldUnlike = isLiked(playlist)
        let request: APIRequest = shouldUnlike ? .unlike(playlist) : .like(playlist)

        perform(request, description: "like playlist") { [weak self] in
            guard let self = self else { return }
            if shouldUnlike {
                self.playlists.removeAll { $0 == playlist }
            }
            else if !self.playlists.contains(playlist) {
                self.playlists.append(playlist)
            }
        }
    }

    func toggleRepost(_ track: Track) {
        let request: APIRequest = isReposted(track) ? .unrepost(track) : .repost(track)
        perform(request, description: "repost track") { [weak self] in self?.reloadPosts() }
    }

    func toggleRepost(_ playlist: UserPlaylist) {
        let request: APIRequest = isReposted(playlist) ? .unrepost(playlist) : .repost(playlist)
        perform(request, description: "repost playlist") { [weak self] in self?.reloadPosts() }
    }

    private func perform<T>(_ request: APIRequest<T>, description: String, onSuccess: @escaping () -> ()) {
        let id = UUID()
        // `receive(on:)` guarantees that the completion is delivered after the subscription is stored
        actionSubscriptions[id] = SoundCloud.shared.perform(request)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case let .failure(error) = completion  {
                    print("Failed to \(description): \(error)")
                }
                self?.actionSubscriptions[id] = nil
            }, receiveValue: onSuccess)
    }

}

extension Array where Element == Post {

    func isReposted(_ track: Track) -> Bool {
        return contains { $0.isRepost && $0.isTrack && $0.tracks.first == track }
    }

    func isReposted(_ playlist: UserPlaylist) -> Bool {
        return contains { $0.isRepost && $0.playlist == playlist }
    }

}

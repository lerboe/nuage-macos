//
//  Library.swift
//  Nuage
//
//  Created by Laurin Brandner on 23.10.26.
//

import Foundation
import Observation
import SoundCloud

private let userKey = "user"

/// Holds the logged in user's playlists, likes and posts and performs the actions modifying them.
@MainActor
@Observable
final class Library {

    private(set) var playlists = [AnyPlaylist]()
    private(set) var likes = [Track]()
    private(set) var posts = [Post]()

    @ObservationIgnored private var userObservation: Task<Void, Never>?
    @ObservationIgnored private var loadedUserID: String?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var postsTask: Task<Void, Never>?

    init() {
        userObservation = Task { [weak self] in
            // Emits the current user first, then every change
            for await user in Observations({ @MainActor in SoundCloud.shared.user }) {
                self?.userDidChange(user)
            }
        }
    }

    private func userDidChange(_ user: User?) {
        // Persist the user so that it's available right away on the next launch
        let defaults = UserDefaults.standard
        if let user = user, let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: userKey)
        }
        else {
            defaults.removeObject(forKey: userKey)
        }

        // Reloading the user from the API emits the same user again
        guard let user = user,
              user.id != loadedUserID,
              SoundCloud.shared.accessToken != nil else { return }
        loadedUserID = user.id

        reloadTask?.cancel()
        reloadTask = Task {
            async let playlists: () = reloadPlaylists()
            async let likes: () = reloadLikes(of: user)
            async let posts: () = reloadPosts(of: user)
            _ = await (playlists, likes, posts)
        }
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

    private func reloadPlaylists() async {
        do {
            playlists = try await SoundCloud.shared.get(all: .library()).map { $0.item }
        }
        catch {
            guard !Task.isCancelled else { return }
            print("Failed to load playlists: \(error)")
        }
    }

    private func reloadLikes(of user: User) async {
        do {
            likes = try await SoundCloud.shared.get(all: .trackLikes(of: user)).map { $0.item }
        }
        catch {
            guard !Task.isCancelled else { return }
            print("Failed to load likes: \(error)")
        }
    }

    private func reloadPosts(of user: User) async {
        do {
            posts = try await SoundCloud.shared.get(all: .stream(of: user))
        }
        catch {
            guard !Task.isCancelled else { return }
            print("Failed to load posts: \(error)")
        }
    }

    private func reloadPosts() {
        guard let user = SoundCloud.shared.user else { return }

        // A newer reload makes a still running one obsolete
        postsTask?.cancel()
        postsTask = Task { await reloadPosts(of: user) }
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
        // Not tied to a view, the request should finish even if the view that triggered it disappears
        Task {
            do {
                try await SoundCloud.shared.perform(request)
                onSuccess()
            }
            catch {
                print("Failed to \(description): \(error)")
            }
        }
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

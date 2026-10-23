//
//  NuageApp.swift
//  Nuage
//
//  Created by Laurin Brandner on 06.12.20.
//

import SwiftUI
import Combine
import SoundCloud

private let accessTokenKey = "accessToken"
private let accessTokenExpiryDateKey = "accessTokenExpiryDate"
private let userKey = "user"
private let playlistsKey = "playlists"
private let likesKey = "likes"
private let postsKey = "posts"

private struct ShowCreatedPlaylistsKey: EnvironmentKey {
    
    static let defaultValue = true
    
}

private struct ShowLikedPlaylistsKey: EnvironmentKey {
    
    static let defaultValue = true
    
}

private struct PlaylistKey: EnvironmentKey {
    
    static let defaultValue = [AnyPlaylist]()
    
}

private struct LikesKey: EnvironmentKey {
    
    static let defaultValue = [Track]()
    
}

private struct PostsKey: EnvironmentKey {
    
    static let defaultValue = [Post]()
    
}


private struct ToggleLikeTrackKey: EnvironmentKey {
    
    static let defaultValue: (Track) -> () -> () = { _ in return { fatalError("Did not set the toggleLike action") } }
    
}

private struct ToggleRepostTrackKey: EnvironmentKey {
    
    static let defaultValue: (Track) -> () -> () = { _ in return { fatalError("Did not set the toggleRepost action") } }
    
}


private struct ToggleLikePlaylistKey: EnvironmentKey {
    
    static let defaultValue: (AnyPlaylist) -> () -> () = { _ in return { fatalError("Did not set the toggleLike action") } }
    
}

private struct ToggleRepostPlaylistKey: EnvironmentKey {
    
    static let defaultValue: (UserPlaylist) -> () -> () = { _ in return { fatalError("Did not set the toggleRepost action") } }
    
}

extension EnvironmentValues {
    
    var showCreatedPlaylists: Bool {
        get { self[ShowCreatedPlaylistsKey.self] }
        set { self[ShowCreatedPlaylistsKey.self] = newValue }
    }
    
    var showLikedPlaylists: Bool {
        get { self[ShowLikedPlaylistsKey.self] }
        set { self[ShowLikedPlaylistsKey.self] = newValue }
    }
    
    var playlists: [AnyPlaylist] {
        get { self[PlaylistKey.self] }
        set { self[PlaylistKey.self] = newValue }
    }
    
    var likes: [Track] {
        get { self[LikesKey.self] }
        set { self[LikesKey.self] = newValue }
    }
    
    var posts: [Post] {
        get { self[PostsKey.self] }
        set { self[PostsKey.self] = newValue }
    }
    
    var toggleLikeTrack: (Track) -> () -> () {
        get { self[ToggleLikeTrackKey.self] }
        set { self[ToggleLikeTrackKey.self] = newValue }
    }
    
    var toggleRepostTrack: (Track) -> () -> () {
        get { self[ToggleRepostTrackKey.self] }
        set { self[ToggleRepostTrackKey.self] = newValue }
    }
    
    var toggleLikePlaylist: (AnyPlaylist) -> () -> () {
        get { self[ToggleLikePlaylistKey.self] }
        set { self[ToggleLikePlaylistKey.self] = newValue }
    }
    
    var toggleRepostPlaylist: (UserPlaylist) -> () -> () {
        get { self[ToggleRepostPlaylistKey.self] }
        set { self[ToggleRepostPlaylistKey.self] = newValue }
    }
    
}


class CommandSubject: ObservableObject {
    
    var filter = PassthroughSubject<(), Never>()
    var search = PassthroughSubject<(), Never>()
    
}

@main
struct NuageApp: App {
    
    @StateObject private var player = StreamPlayer()
    private var commandSubjects = CommandSubject()
    
    @State private var showCreatedPlaylists = true
    @State private var showLikedPlaylists = true
    
    @State private var playlists: [AnyPlaylist]
    @State private var likes: [Track]
    @State private var posts: [Post]
    @State private var loggedIn: Bool
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some Scene {
        WindowGroup {
            if loggedIn {
                MainView()
                    .frame(minWidth: 600, minHeight: 400)
                    .environmentObject(player)
                    .environmentObject(commandSubjects)
                    .environment(\.showCreatedPlaylists, showCreatedPlaylists)
                    .environment(\.showLikedPlaylists, showLikedPlaylists)
                    .environment(\.playlists, playlists)
                    .environment(\.likes, likes)
                    .environment(\.posts, posts)
                    .environment(\.toggleLikeTrack, toggleLike)
                    .environment(\.toggleRepostTrack, toggleRepost)
                    .environment(\.toggleLikePlaylist, toggleLike)
                    .environment(\.toggleRepostPlaylist, toggleRepost)
                    .onAppear {
                        reloadLibrary()
                        reloadLikes()
                        reloadPosts()
                        
                        // Whenever the current stream changes, add it to the SoundCloud history
                        player.$currentStream
                            .filter { $0 != nil}
                            .flatMap { SoundCloud.shared.perform(.addToHistory($0!)) }
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion {
                                    print("Failed to add track to history: \(error)")
                                }
                            }, receiveValue: { _ in })
                            .store(in: &subscriptions)
                    }
            }
            else {
                LoginView { accessToken, expiryDate in
                    let defaults = UserDefaults.standard
                    Keychain.set(accessToken, forKey: accessTokenKey)
                    defaults.set(expiryDate, forKey: accessTokenExpiryDateKey)
                    SoundCloud.shared.accessToken = accessToken
                    loggedIn = true
                }
            }
        }
        .defaultSize(width: 800, height: 400)
        .commands(content: commands)
    }
    
    @CommandsBuilder private func commands() -> some Commands {
        CommandGroup(after: .textEditing) {
            Button("Filter") {
                commandSubjects.filter.send()
            }.keyboardShortcut("f", modifiers: .command)
            Button("Search") {
                commandSubjects.search.send()
            }.keyboardShortcut("l", modifiers: .command)
        }
        CommandGroup(before: .toolbar) {
            Menu("Playlists") {
                Toggle("Show Created", isOn: $showCreatedPlaylists)
                Toggle("Show Liked", isOn: $showLikedPlaylists)
            }
        }
        playbackMenu()
    }
    
    @CommandsBuilder private func playbackMenu() -> some Commands {
        CommandMenu("Playback") {
            let playbackToggleTitle = player.isPlaying ? "Pause" : "Play"
            Button(playbackToggleTitle, action: player.togglePlayback)
            
            Divider()
            
            playbackControls()
            
            Divider()
            
            Toggle("Shuffle", isOn: $player.shuffleQueue)
                .keyboardShortcut("s", modifiers: [.command])

            Toggle("Repeat", isOn: $player.repeatQueue)
                .keyboardShortcut("r", modifiers: [.command])
            
            Divider()
            
            Button("Volume Up") {
                player.volume += 0.05
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])

            Button("Volume Down") {
                player.volume -= 0.05
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
        }
    }
    
    @ViewBuilder private func playbackControls() -> some View {
        Button("Next", action: player.advanceForward)
            .keyboardShortcut(.rightArrow, modifiers: .command)
        
        Button("Previous", action: player.advanceBackward)
            .keyboardShortcut(.leftArrow, modifiers: .command)
        
        Button("Seek Forward", action: player.seekForward)
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        
        Button("Seek Backward", action: player.seekBackward)
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
    }
    
    init() {
        let MB = 1024*1024
        URLCache.shared = URLCache(memoryCapacity: 10*MB, diskCapacity: 20*MB)
        URLSession.shared.configuration.requestCachePolicy = .returnCacheDataElseLoad
        
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: userKey) {
            do {
                SoundCloud.shared.user = try JSONDecoder().decode(User.self, from: data)
            }
            catch {
                defaults.removeObject(forKey: userKey)
                print("Failed to load user from UserDefaults: \(error)")
            }
        }
        // Migrate any token still stored in plaintext by an earlier version
        if let legacyToken = defaults.string(forKey: accessTokenKey) {
            Keychain.set(legacyToken, forKey: accessTokenKey)
            defaults.removeObject(forKey: accessTokenKey)
        }

        let token = Keychain.string(forKey: accessTokenKey)
        let expiryDate = defaults.object(forKey: accessTokenExpiryDateKey)

        _loggedIn = State(initialValue: false)
        if let token = token {
            if let exipryDate = expiryDate as? Date, exipryDate < Date() {
                Keychain.set(nil, forKey: accessTokenKey)
                defaults.removeObject(forKey: accessTokenExpiryDateKey)
            }
            else {
                SoundCloud.shared.accessToken = token
                _loggedIn = State(initialValue: true)
            }
        }
        
        // A cache that fails to decode is only a cache miss, the content is
        // refetched on appear. Never let it take the app down on launch.
        playlists = defaults.cachedValue([AnyPlaylist].self, forKey: playlistsKey) ?? []
        likes = defaults.cachedValue([Track].self, forKey: likesKey) ?? []
        posts = defaults.cachedValue([Post].self, forKey: postsKey) ?? []
        
        playlists.publisher.sink { defaults.cache($0, forKey: playlistsKey) }
            .store(in: &subscriptions)

        likes.publisher.sink { defaults.cache($0, forKey: likesKey) }
            .store(in: &subscriptions)

        posts.publisher.sink { defaults.cache($0, forKey: postsKey) }
            .store(in: &subscriptions)

        SoundCloud.shared.$user.sink { user in
            if let user = user {
                defaults.cache(user, forKey: userKey)
            }
            else {
                defaults.removeObject(forKey: userKey)
            }
        }
        .store(in: &subscriptions)
    }
    
    private func reloadLibrary() {
        SoundCloud.shared.get(all: .library())
            .map { $0.map { $0.item } }
            .replaceError(with: playlists)
            .receive(on: RunLoop.main)
            .assign(to: \.playlists, on: self)
            .store(in: &subscriptions)
    }
    
    private func reloadLikes() {
        SoundCloud.shared.$user
            .filter { $0 != nil}
            .flatMap { SoundCloud.shared.get(all: .trackLikes(of: $0!)) }
            .map { $0.map { $0.item } }
            .replaceError(with: likes)
            .receive(on: RunLoop.main)
            .assign(to: \.likes, on: self)
            .store(in: &subscriptions)
    }
    
    private func reloadPosts() {
        SoundCloud.shared.$user
            .filter { $0 != nil}
            .flatMap { SoundCloud.shared.get(all: .stream(of: $0!)) }
            .replaceError(with: posts)
            .receive(on: RunLoop.main)
            .assign(to: \.posts, on: self)
            .store(in: &subscriptions)
    }
    
    private func toggleLike(_ track: Track) -> () -> () {
        return {
            let shouldUnlike = likes.contains(track)
            let request: APIRequest = shouldUnlike ? .unlike(track) : .like(track)
            
            return SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion  {
                        print("Failed to like track: \(error)")
                    }
                }, receiveValue: {
                    if shouldUnlike {
                        likes.removeAll { $0 == track }
                    }
                    else {
                        likes.append(track)
                    }
                })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleLike(_ playlist: AnyPlaylist) -> () -> () {
        return {
            let shouldUnlike = playlists.contains(playlist)
            let request: APIRequest = shouldUnlike ? .unlike(playlist) : .like(playlist)
            
            return SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion  {
                        print("Failed to like playlist: \(error)")
                    }
                }, receiveValue: {
                    if shouldUnlike {
                        playlists.removeAll { $0 == playlist }
                    }
                    else {
                        playlists.append(playlist)
                    }
                })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleRepost(_ track: Track) -> () -> () {
        return {
            let shouldDeleteRepost = posts.filter { $0.isRepost && $0.isTrack }
                .map { $0.tracks.first! }
                .contains(track)
            let request: APIRequest = shouldDeleteRepost ? .unrepost(track) : .repost(track)
            
            return SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion  {
                        print("Failed to repost track: \(error)")
                    }
                }, receiveValue: { reloadPosts() })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleRepost(_ playlist: UserPlaylist) -> () -> () {
        return {
            let shouldDeleteRepost = posts.filter { $0.isRepost && !$0.isTrack }
                .compactMap { $0.playlist }
                .contains(playlist)
            
            let request: APIRequest = shouldDeleteRepost ? .unrepost(playlist) : .repost(playlist)
            
            return SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion  {
                        print("Failed to repost playlist: \(error)")
                    }
                }, receiveValue: { reloadPosts() })
                .store(in: &subscriptions)
        }
    }
    
}

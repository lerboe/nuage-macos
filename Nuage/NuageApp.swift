//
//  NuageApp.swift
//  Nuage
//
//  Created by Laurin Brandner on 06.12.20.
//

import SwiftUI
import Observation
import SoundCloud

private let accessTokenKey = "accessToken"
private let accessTokenExpiryDateKey = "accessTokenExpiryDate"

/// Keys of a library cache that was never read back successfully, see `NuageApp.init`.
private let legacyCacheKeys = ["playlists", "likes", "posts"]

/// Cached responses that weren't used for this long are deleted.
private let responseCacheMaxAge: TimeInterval = 7*24*60*60
/// The least recently used responses are deleted when the cache grows beyond this size in bytes.
private let responseCacheMaxSize = 50*1024*1024

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


/// Forwards menu commands to the views handling them.
/// Views react to changes of the request counters with `onChange(of:)`.
@MainActor
@Observable
final class MenuCommands {
    
    private(set) var searchRequests = 0
    
    func requestSearch() {
        searchRequests += 1
    }
    
}

@main
struct NuageApp: App {
    
    @State private var player = StreamPlayer()
    @State private var sonosBrowser = SonosBrowser()
    @State private var library = Library()
    @State private var menuCommands = MenuCommands()
    
    @State private var showCreatedPlaylists = true
    @State private var showLikedPlaylists = true
    @AppStorage(showSonosSpeakersKey) private var showSonosSpeakers = false
    @AppStorage(showAirPlaySpeakersKey) private var showAirPlaySpeakers = true
    
    @State private var loggedIn: Bool
    
    var body: some Scene {
        // An explicit id gives the window a stable frame autosave name.
        // Without one SwiftUI derives it from the content's type name,
        // which changes whenever the view hierarchy does.
        WindowGroup(id: "main") {
            // A ZStack rather than a Group, which would apply the modifier
            // to each branch separately. Login and main share one window.
            ZStack {
                if loggedIn {
                    MainView()
                        .frame(minWidth: 600, minHeight: 400)
                        .environment(player)
                        .environment(sonosBrowser)
                        .environment(menuCommands)
                        .environment(\.showCreatedPlaylists, showCreatedPlaylists)
                        .environment(\.showLikedPlaylists, showLikedPlaylists)
                        .environment(\.playlists, library.playlists)
                        .environment(\.likes, library.likes)
                        .environment(\.posts, library.posts)
                        .environment(\.toggleLikeTrack) { track in { library.toggleLike(track) } }
                        .environment(\.toggleRepostTrack) { track in { library.toggleRepost(track) } }
                        .environment(\.toggleLikePlaylist) { playlist in { library.toggleLike(playlist) } }
                        .environment(\.toggleRepostPlaylist) { playlist in { library.toggleRepost(playlist) } }
                }
                else {
                    LoginView { accessToken, expiryDate in
                        // The cookie handler fires on every navigation, only log in once
                        guard !loggedIn else { return }
                        
                        let defaults = UserDefaults.standard
                        Keychain.set(accessToken, forKey: accessTokenKey)
                        defaults.set(expiryDate, forKey: accessTokenExpiryDateKey)
                        SoundCloud.shared.accessToken = accessToken
                        loggedIn = true
                    }
                }
            }
            // Finds the speakers at launch and when they are enabled in the menu.
            // The local network isn't accessed at all while Sonos is disabled.
            .task(id: showSonosSpeakers) {
                if showSonosSpeakers {
                    await sonosBrowser.start()
                }
                else {
                    sonosBrowser.stop()
                }
            }
        }
        .defaultSize(width: 800, height: 400)
        // Without it, no window opens at launch if the window was closed before quitting,
        // because then the restored state contains no windows.
        .defaultLaunchBehavior(.presented)
        .commands(content: commands)
    }
    
    @CommandsBuilder private func commands() -> some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search", action: menuCommands.requestSearch)
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(before: .toolbar) {
            Menu("Playlists") {
                Toggle("Show Created", isOn: $showCreatedPlaylists)
                Toggle("Show Liked", isOn: $showLikedPlaylists)
            }
            Menu("Speakers") {
                Toggle("Sonos", isOn: $showSonosSpeakers)
                Toggle("AirPlay", isOn: $showAirPlaySpeakers)
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

            Picker("Speed", selection: $player.playbackRate) {
                ForEach(StreamPlayer.playbackRates, id: \.self) { rate in
                    Text(rate.formatted() + "x")
                        .tag(rate)
                }
            }
            // Sonos speakers only play at the normal speed
            .disabled(player.sonosGroup != nil)

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

        // Shows the content right away when a window appears, until it's reloaded
        let cacheDirectory = URL.cachesDirectory.appending(path: "Responses", directoryHint: .isDirectory)
        SoundCloud.shared.cache = ResponseCache(directory: cacheDirectory,
                                                maxAge: responseCacheMaxAge,
                                                maxSize: responseCacheMaxSize)
        
        let defaults = UserDefaults.standard
        
        // Previous versions wrote a library cache that could never be decoded again
        legacyCacheKeys.forEach(defaults.removeObject)
        
        // Migrate a token still stored in plaintext by an earlier version,
        // unless the Keychain already holds one. Never leave the plaintext copy behind.
        if let legacyToken = defaults.string(forKey: accessTokenKey) {
            if Keychain.string(forKey: accessTokenKey) == nil {
                Keychain.set(legacyToken, forKey: accessTokenKey)
            }
            defaults.removeObject(forKey: accessTokenKey)
        }
        
        var loggedIn = false
        if let token = Keychain.string(forKey: accessTokenKey) {
            if let expiryDate = defaults.object(forKey: accessTokenExpiryDateKey) as? Date, expiryDate >= Date() {
                Library.restoreUser()
                SoundCloud.shared.accessToken = token
                loggedIn = true
            }
            else {
                // Expired, or no expiry date to check against
                Keychain.set(nil, forKey: accessTokenKey)
                defaults.removeObject(forKey: accessTokenExpiryDateKey)
                Library.forgetUser()
            }
        }
        _loggedIn = State(initialValue: loggedIn)
    }
    
}

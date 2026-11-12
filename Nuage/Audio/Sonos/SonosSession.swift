//
//  SonosSession.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation

/// Controls playback on a Sonos group. The speakers stream the audio themselves,
/// the session sends them the tracks and polls their state.
@MainActor
final class SonosSession {

    enum Event {
        /// `position` is nil if the speaker isn't playing the current track.
        case status(isPlaying: Bool, position: TimeInterval?, volume: Float)
        case trackDidFinish
        /// The speaker became unreachable or started playing something else.
        case didDisconnect
    }

    let group: SonosGroup
    var onEvent: ((Event) -> ())?

    private let client: SonosClient
    private var pollTask: Task<Void, Never>?

    /// Commands are chained so that they reach the speaker in order.
    private var lastCommand: Task<Void, Never>?
    private var pendingCommands = 0
    private var commandGeneration = 0
    private var requestedVolume: Int?

    private(set) var currentTrackID: String?
    private var currentTrack: TrackInfo?
    private var currentSource: SonosSource?
    private var currentURI: URL?
    /// Whether the speaker started playing the current track, so that a stop means it ended.
    private var didStartCurrentTrack = false

    /// A relayed stream starts at this position, the speaker reports its position relative to it.
    private var positionOffset: TimeInterval = 0
    /// Whether the user wants the speaker to play, as opposed to being paused.
    private var wantsPlayback = false
    /// The track restarts at this position once resumed, e.g. after a relayed stream was seeked
    /// while paused or the speaker lost its connection.
    private var pendingRestartPosition: TimeInterval?
    /// The last position the speaker reported for the current track.
    private var lastPosition: TimeInterval = 0
    /// The length of the audio the speaker plays, which can be shorter than the track (e.g. a preview).
    private var streamDuration: TimeInterval = 0

    /// The details the speaker shows for the current track.
    struct TrackInfo {
        var title: String
        var artist: String
        var artworkURL: URL?
        var duration: TimeInterval
    }

    init(group: SonosGroup) {
        self.group = group
        self.client = SonosClient(baseURL: group.coordinatorURL)
    }

    isolated deinit {
        pollTask?.cancel()
    }

    // MARK: - Commands

    /// Plays the track from `source` on the speakers, starting at `position`.
    func load(trackID: String, info: TrackInfo, source: SonosSource, at position: TimeInterval) {
        currentTrackID = trackID
        currentTrack = info
        currentSource = source
        wantsPlayback = true
        pendingRestartPosition = nil
        restart(at: position)
    }

    /// Hands the current track to the speaker again, starting at `position`.
    /// Relayed streams can't be seeked, they're requested from `position` instead.
    private func restart(at position: TimeInterval) {
        lastPosition = position
        streamDuration = 0

        switch currentSource {
        case .file(let url)?:
            positionOffset = 0
            start(url, mimeType: "audio/mpeg", seekingTo: position)
        case let .relay(mimeType, duration, url)?:
            positionOffset = position
            streamDuration = duration
            start(url(position), mimeType: mimeType, seekingTo: nil)
        case nil:
            break
        }
    }

    private func start(_ url: URL, mimeType: String, seekingTo position: TimeInterval?) {
        guard let info = currentTrack else { return }

        currentURI = url
        didStartCurrentTrack = false

        let metadata = SonosClient.metadata(title: info.title,
                                            artist: info.artist,
                                            artworkURL: info.artworkURL,
                                            duration: info.duration,
                                            uri: url,
                                            mimeType: mimeType)
        perform("load") { client in
            try await client.setTransportURI(url, metadata: metadata)
            try await client.play()
            if let position = position, position >= 1 {
                try await client.seek(to: position)
            }
        }
    }

    func play() {
        wantsPlayback = true
        if let position = pendingRestartPosition {
            pendingRestartPosition = nil
            restart(at: position)
            return
        }

        perform("play") { try await $0.play() }
    }

    func pause() {
        wantsPlayback = false
        perform("pause") { try await $0.pause() }
    }

    func stop() {
        currentTrackID = nil
        currentTrack = nil
        currentSource = nil
        currentURI = nil
        didStartCurrentTrack = false
        wantsPlayback = false
        pendingRestartPosition = nil
        perform("stop") { try await $0.stop() }
    }

    func seek(to position: TimeInterval) {
        lastPosition = position

        var isRelayed = false
        if case .relay? = currentSource {
            isRelayed = true
        }

        // A track that has to be restarted anyway just starts at the new position
        if pendingRestartPosition != nil || (isRelayed && !wantsPlayback) {
            pendingRestartPosition = position
        }
        else if isRelayed {
            restart(at: position)
        }
        else {
            perform("seek") { try await $0.seek(to: position) }
        }
    }

    func setVolume(_ volume: Float) {
        let isQueued = requestedVolume != nil
        requestedVolume = Int((volume * 100).rounded())
        // A queued command picks up the latest value, which coalesces quick slider changes
        guard !isQueued else { return }

        perform("setVolume") { [weak self] client in
            guard let volume = self?.requestedVolume else { return }
            self?.requestedVolume = nil
            try await client.setGroupVolume(volume)
        }
    }

    private func perform(_ name: String, command: @escaping @MainActor (SonosClient) async throws -> ()) {
        let previousCommand = lastCommand
        let client = client
        pendingCommands += 1
        commandGeneration += 1

        // The command doesn't retain the session so that e.g. a final pause still runs after invalidation
        lastCommand = Task { [weak self] in
            await previousCommand?.value
            do {
                try await command(client)
            }
            catch {
                print("Sonos command \(name) failed: \(error)")
            }
            self?.pendingCommands -= 1
        }
    }

    // MARK: - Polling

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self = self else { return }

                do {
                    try await self.poll()
                    failures = 0
                }
                catch {
                    failures += 1
                    if failures >= 5 {
                        print("Lost connection to Sonos: \(error)")
                        self.onEvent?(.didDisconnect)
                        return
                    }
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Stops polling. Queued commands are still sent.
    func invalidate() {
        onEvent = nil
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async throws {
        let generation = commandGeneration
        async let state = client.transportState()
        async let info = client.positionInfo()
        async let volume = client.groupVolume()
        let (currentState, currentInfo, currentVolume) = try await (state, info, volume)

        // The state is outdated if commands were sent in the meantime
        guard !Task.isCancelled, pendingCommands == 0, generation == commandGeneration else { return }

        // The speaker might report the URI in a slightly different form, so only the path is compared
        let isPlayingCurrentTrack = currentURI.map { currentInfo.trackURI.contains($0.path) } ?? false

        if didStartCurrentTrack && !isPlayingCurrentTrack && !currentInfo.trackURI.isEmpty {
            // Another app took over the speakers
            onEvent?(.didDisconnect)
            return
        }

        if isPlayingCurrentTrack && currentState == .playing {
            didStartCurrentTrack = true
        }

        if didStartCurrentTrack && currentState == .stopped {
            didStartCurrentTrack = false
            wantsPlayback = false

            // Stopping well before the end means the speaker lost the stream, e.g. its connection to the relay.
            // The track is then paused where it stopped, instead of skipping to the next one.
            let duration = streamDuration
            if duration > 0 && lastPosition < duration - 10 {
                print("Sonos stopped at \(Int(lastPosition))s of \(Int(duration))s, resuming from there on play")
                pendingRestartPosition = lastPosition
                onEvent?(.status(isPlaying: false, position: lastPosition, volume: Float(currentVolume) / 100))
                return
            }

            // Playing a finished relayed stream again has to request it from the start
            if case .relay? = currentSource {
                pendingRestartPosition = 0
            }
            onEvent?(.trackDidFinish)
            return
        }

        let isPlaying = isPlayingCurrentTrack && (currentState == .playing || currentState == .transitioning)
        let position = pendingRestartPosition ?? (currentInfo.position + positionOffset)
        // A stopped speaker reports 0, which isn't where the track was left off
        if isPlayingCurrentTrack && pendingRestartPosition == nil && currentState != .stopped {
            lastPosition = position
            // Files report their length, relayed streams know it from their playlist
            if currentInfo.duration > 0, case .file? = currentSource {
                streamDuration = currentInfo.duration
            }
            if case .relay? = currentSource, let uri = currentURI {
                // Lets the relay continue from here if the speaker requests the stream again
                Task { await SonosRelay.shared.setPlaybackPosition(position, forStreamAt: uri) }
            }
        }
        onEvent?(.status(isPlaying: isPlaying,
                         position: isPlayingCurrentTrack ? position : nil,
                         volume: Float(currentVolume) / 100))
    }

}

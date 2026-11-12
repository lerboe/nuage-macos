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
    private var currentURI: URL?
    /// Whether the speaker started playing the current track, so that a stop means it ended.
    private var didStartCurrentTrack = false

    init(group: SonosGroup) {
        self.group = group
        self.client = SonosClient(baseURL: group.coordinatorURL)
    }

    isolated deinit {
        pollTask?.cancel()
    }

    // MARK: - Commands

    /// Plays the audio file at `url` on the speakers, starting at `position`.
    func load(trackID: String, url: URL, metadata: String, at position: TimeInterval) {
        currentTrackID = trackID
        currentURI = url
        didStartCurrentTrack = false

        perform("load") { client in
            try await client.setTransportURI(url, metadata: metadata)
            try await client.play()
            if position >= 1 {
                try await client.seek(to: position)
            }
        }
    }

    func play() {
        perform("play") { try await $0.play() }
    }

    func pause() {
        perform("pause") { try await $0.pause() }
    }

    func stop() {
        currentTrackID = nil
        currentURI = nil
        didStartCurrentTrack = false
        perform("stop") { try await $0.stop() }
    }

    func seek(to position: TimeInterval) {
        perform("seek") { try await $0.seek(to: position) }
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
            onEvent?(.trackDidFinish)
            return
        }

        let isPlaying = isPlayingCurrentTrack && (currentState == .playing || currentState == .transitioning)
        onEvent?(.status(isPlaying: isPlaying,
                         position: isPlayingCurrentTrack ? currentInfo.position : nil,
                         volume: Float(currentVolume) / 100))
    }

}

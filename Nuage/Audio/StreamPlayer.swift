//
//  StreamPlayer.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import AppKit
import AVFoundation
import MediaPlayer
import Observation
import SoundCloud

protocol Streamable {

    func prepare() async throws -> AVURLAsset

}

private let volumeKey = "volume"
private let shuffleQueueKey = "shuffleQueue"
private let repeatQueueKey = "repeatQueue"
private let playbackRateKey = "playbackRate"

@MainActor
@Observable
final class StreamPlayer {

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var didPlayToEndTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var timeControlStatusObservation: NSKeyValueObservation?

    @ObservationIgnored private(set) var player: AVPlayer

    /// The tracks in the order they were enqueued.
    private(set) var queue = [Track]()

    /// Maps positions in the playback order to indices of `queue`.
    private var queueOrder = [Int]()

    /// The position of the current stream in the playback order, see `orderedQueue`.
    private(set) var currentStreamIndex: Int? {
        didSet {
            currentStream = currentStreamIndex.map { queue[queueOrder[$0]] }
        }
    }

    /// The queue in playback order, i.e. taking shuffling into account.
    var orderedQueue: [Track] {
        return queueOrder.map { queue[$0] }
    }

    private(set) var currentStream: Track? {
        didSet {
            // Add every new track to the SoundCloud history
            guard let track = currentStream, track != oldValue else { return }
            Task {
                do {
                    try await SoundCloud.shared.perform(.addToHistory(track))
                }
                catch {
                    print("Failed to add track to history: \(error)")
                }
            }
        }
    }

    var shuffleQueue: Bool {
        didSet {
            UserDefaults.standard.set(shuffleQueue, forKey: shuffleQueueKey)
            guard shuffleQueue != oldValue else { return }

            // Reorder the queue so that the current track stays the current track
            let current = currentStreamIndex.map { queueOrder[$0] }
            queueOrder = order(forQueueOfCount: queue.count, startingWith: current)
            if let current = current {
                currentStreamIndex = queueOrder.firstIndex(of: current)
            }
        }
    }

    var repeatQueue: Bool {
        didSet {
            UserDefaults.standard.set(repeatQueue, forKey: repeatQueueKey)
        }
    }

    static let playbackRates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    /// The speed of the playback on this Mac. Sonos speakers only support the normal speed.
    var playbackRate: Float = 1 {
        didSet {
            guard playbackRate != oldValue else { return }

            UserDefaults.standard.set(playbackRate, forKey: playbackRateKey)
            applyPlaybackRate()
            updateNowPlayingInfo()
        }
    }

    var volume: Float = 0.5 {
        didSet {
            let clampedVolume = min(max(volume, 0), 1)
            if clampedVolume != volume {
                volume = clampedVolume
            }

            guard shouldForwardVolume else { return }

            if let sonosSession = sonosSession {
                // The speaker's volume is independent from the one on this Mac
                sonosSession.setVolume(volume)
            }
            else {
                player.volume = volume
                UserDefaults.standard.set(volume, forKey: volumeKey)
            }
        }
    }
    @ObservationIgnored private var shouldForwardVolume = true

    @ObservationIgnored private var shouldSeek = true
    /// Identifies the most recent seek, so that only its completion is handled.
    @ObservationIgnored private var seekGeneration = 0
    /// While seeking, the player still reports the previous time, which must not override `progress`.
    @ObservationIgnored private var isSeeking = false
    var progress: TimeInterval = 0.0 {
        didSet {
            guard shouldSeek else { return }

            let duration = TimeInterval(currentStream?.duration ?? 0)
            let clampedProgress = duration > 0 ? min(max(progress, 0), duration) : max(progress, 0)
            if clampedProgress != progress {
                progress = clampedProgress
            }

            let time = CMTime(seconds: progress, preferredTimescale: 600)
            if let sonosSession = sonosSession {
                sonosSession.seek(to: progress)
            }
            else {
                seek(to: time)
            }
            updateNowPlayingInfo(with: time)
        }
    }

    private(set) var isPlaying = false

    /// The Sonos group that plays the audio, nil if it plays on this Mac.
    private(set) var sonosGroup: SonosGroup?
    @ObservationIgnored private var sonosSession: SonosSession?

    @ObservationIgnored private var nowPlayingTrackID: String?

    // MARK: - Initialization

    init() {
        self.player = AVPlayer()
        self.player.allowsExternalPlayback = false

        let defaults = UserDefaults.standard
        self.shuffleQueue = defaults.bool(forKey: shuffleQueueKey)
        self.repeatQueue = defaults.bool(forKey: repeatQueueKey)
        if defaults.object(forKey: volumeKey) != nil {
            self.volume = min(max(defaults.float(forKey: volumeKey), 0), 1)
        }
        let rate = defaults.float(forKey: playbackRateKey)
        if StreamPlayer.playbackRates.contains(rate) {
            self.playbackRate = rate
        }
        // Property observers aren't called during initialization
        player.volume = volume
        applyPlaybackRate()

        let interval = CMTime(value: 1, timescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self = self, self.sonosSession == nil, !self.isSeeking else { return }
                self.setProgressWithoutSeeking(time.seconds)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.timeControlStatusDidChange()
            }
        }

        addRemoteCommandTargets()
    }

    isolated deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    private func applyPlaybackRate() {
        // `play()` starts at the default rate, a running playback has to be adjusted directly
        player.defaultRate = playbackRate
        if player.rate != 0 {
            player.rate = playbackRate
        }
    }

    private func timeControlStatusDidChange() {
        guard sonosSession == nil else { return }

        isPlaying = (player.timeControlStatus != .paused)
        updateNowPlayingInfo()
    }

    // MARK: - Sonos

    /// Continues playback on `group`, the speakers then stream the audio themselves.
    func play(on group: SonosGroup) {
        guard group.id != sonosGroup?.id else { return }

        let wasPlaying = isPlaying
        let position = progress
        sonosSession?.pause()
        endSonosSession()

        // Stop the local playback, it continues from `progress` when switching back
        streamTask?.cancel()
        didPlayToEndTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)

        let session = SonosSession(group: group)
        session.onEvent = { [weak self] event in
            self?.handle(event)
        }
        sonosSession = session
        sonosGroup = group
        isPlaying = false
        session.start()

        setProgressWithoutSeeking(position)
        if wasPlaying {
            resume()
        }
    }

    /// Continues playback on this Mac and pauses the Sonos group.
    func playOnThisMac() {
        guard let sonosSession = sonosSession else { return }

        let wasPlaying = isPlaying
        sonosSession.pause()
        endSonosSession()

        if wasPlaying {
            resume()
        }
    }

    private func endSonosSession() {
        guard let sonosSession = sonosSession else { return }

        streamTask?.cancel()
        sonosSession.invalidate()
        self.sonosSession = nil
        sonosGroup = nil
        isPlaying = false

        // Restore the volume of this Mac
        let defaults = UserDefaults.standard
        if defaults.object(forKey: volumeKey) != nil {
            setVolumeWithoutForwarding(defaults.float(forKey: volumeKey))
        }
        player.volume = volume
        updateNowPlayingInfo()
    }

    private func handle(_ event: SonosSession.Event) {
        switch event {
        case let .status(isPlaying, position, volume):
            self.isPlaying = isPlaying
            if let position = position {
                setProgressWithoutSeeking(position)
            }
            setVolumeWithoutForwarding(volume)
            updateNowPlayingInfo()
        case .trackDidFinish:
            advanceForward()
        case .didDisconnect:
            endSonosSession()
        }
    }

    /// Plays `track` on the Sonos group, starting at `position`.
    private func load(_ track: Track, on session: SonosSession, at position: TimeInterval) {
        isPlaying = true

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            do {
                // The URL is resolved right before playing since it expires
                let url = try await track.audioFileURL()

                // Sonos speakers can't play HLS streams, this Mac relays them instead
                let source: SonosSource
                if url.pathExtension == "m3u8" {
                    source = try await SonosRelay.shared.source(playlistURL: url,
                                                                resolvePlaylistURL: { try await track.audioFileURL() },
                                                                reachableFrom: session.group.coordinatorURL)
                }
                else {
                    source = .file(url)
                }
                guard let self = self, !Task.isCancelled, self.sonosSession === session else { return }

                let info = SonosSession.TrackInfo(title: track.title,
                                                  artist: track.user.username,
                                                  artworkURL: track.artworkURL ?? track.user.avatarURL,
                                                  duration: TimeInterval(track.duration))
                session.load(trackID: track.id, info: info, source: source, at: position)
                self.updateNowPlayingInfo()
            }
            catch {
                guard !Task.isCancelled else { return }
                print("Failed to stream track to Sonos: \(error)")
                self?.isPlaying = false
            }
        }
    }

    // MARK: - Playback

    func restartPlayback() {
        if let sonosSession = sonosSession {
            guard let track = currentStream else { return }

            setProgressWithoutSeeking(0)
            if sonosSession.currentTrackID == track.id {
                sonosSession.seek(to: 0)
                sonosSession.play()
            }
            else {
                load(track, on: sonosSession, at: 0)
            }
            return
        }

        player.seek(to: .zero)
        player.play()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        }
        else {
            resume()
        }
    }

    /// Resumes playback of the track at position `startIndex` of `orderedQueue`.
    /// If `startIndex` is nil, the current track (or the first one in the queue) is resumed.
    func resume(from startIndex: Int? = nil) {
        guard let idx = startIndex ?? currentStreamIndex ?? (queue.isEmpty ? nil : 0),
              queueOrder.indices.contains(idx) else { return }

        let newStream = queue[queueOrder[idx]]

        if let sonosSession = sonosSession {
            let isCurrentStream = (currentStream == newStream)
            currentStreamIndex = idx

            if isCurrentStream && sonosSession.currentTrackID == newStream.id {
                isPlaying = true
                sonosSession.play()
            }
            else {
                // Continue where the track was left off, e.g. after switching from this Mac
                let position = isCurrentStream ? progress : 0
                setProgressWithoutSeeking(position)
                load(newStream, on: sonosSession, at: position)
            }
            return
        }

        if currentStream == newStream && player.currentItem != nil {
            currentStreamIndex = idx
            player.play()
            return
        }

        // Continue where the track was left off, e.g. after switching from Sonos
        let position = (currentStream == newStream) ? progress : 0
        currentStreamIndex = idx
        player.replaceCurrentItem(with: nil)
        setProgressWithoutSeeking(position)

        // Cancel the loading of a previously requested track,
        // so that a slow response can't override a newer selection.
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            do {
                let asset = try await newStream.prepare()
                guard let self = self, !Task.isCancelled else { return }

                let item = AVPlayerItem(asset: asset)
                self.player.replaceCurrentItem(with: item)
                if position > 0 {
                    await self.player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                    guard !Task.isCancelled else { return }
                }
                self.player.play()
                self.advanceForwardWhenFinished(playing: item)
                self.updateNowPlayingInfo()
            }
            catch {
                guard !Task.isCancelled else { return }
                print("Failed to stream track: \(error)")
            }
        }
    }

    private func advanceForwardWhenFinished(playing item: AVPlayerItem) {
        didPlayToEndTask?.cancel()
        didPlayToEndTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            for await _ in notifications {
                self?.advanceForward()
                return
            }
        }
    }

    func pause() {
        if let sonosSession = sonosSession {
            // The speakers might not have started yet
            streamTask?.cancel()
            isPlaying = false
            sonosSession.pause()
        }
        else {
            player.pause()
        }
    }

    /// Replaces the queue with `tracks` and starts playing the track at `idx`.
    func play(_ tracks: [Track], from idx: Int) {
        guard tracks.indices.contains(idx) else { return }
        guard !(currentStream == tracks[idx] && queue == tracks) else {
            restartPlayback()
            return
        }

        pause()
        queue = tracks
        queueOrder = order(forQueueOfCount: tracks.count, startingWith: idx)
        currentStreamIndex = nil

        resume(from: queueOrder.firstIndex(of: idx))
    }

    func advanceForward() {
        guard let idx = currentStreamIndex else { return }

        if queueOrder.count > idx + 1 {
            resume(from: idx + 1)
        }
        else if repeatQueue {
            resume(from: 0)
        }
        else {
            reset()
        }
    }

    func advanceBackward() {
        guard let idx = currentStreamIndex else { return }

        let elapsed = sonosSession == nil ? player.currentTime().seconds : progress
        if idx > 0 && elapsed < 15 {
            resume(from: idx - 1)
        }
        else {
            restartPlayback()
        }
    }

    func seekForward() {
        progress += 15
    }

    func seekBackward() {
        progress -= 15
    }

    func reset() {
        pause()
        sonosSession?.stop()
        streamTask?.cancel()
        didPlayToEndTask?.cancel()
        player.replaceCurrentItem(with: nil)
        currentStreamIndex = nil
        queue = []
        queueOrder = []
        setProgressWithoutSeeking(0)
        updateNowPlayingInfo()
    }

    /// Adds `streams` to the queue. If `playNext` is true, they are played right after the current track.
    func enqueue(_ streams: [Track], playNext: Bool = false) {
        guard streams.count > 0 else { return }

        var newIndices = Array(queue.count..<queue.count + streams.count)
        if shuffleQueue {
            newIndices.shuffle()
        }

        queue += streams
        if playNext {
            let position = currentStreamIndex.map { $0 + 1 } ?? 0
            queueOrder.insert(contentsOf: newIndices, at: position)
        }
        else {
            queueOrder += newIndices
        }
    }

    /// Returns the playback order for a queue of `count` tracks.
    /// When shuffling, `start` is moved to the front and the remaining tracks are shuffled.
    private func order(forQueueOfCount count: Int, startingWith start: Int?) -> [Int] {
        let order = Array(0..<count)
        guard shuffleQueue else { return order }

        guard let start = start else { return order.shuffled() }
        return [start] + order.filter { $0 != start }.shuffled()
    }

    /// Seeks the local player to `time`. `progress` keeps the new position while buffering,
    /// it only jumps back to the actual playback position if the seek fails.
    private func seek(to time: CMTime) {
        guard let item = player.currentItem else { return }

        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let finished = await self.player.seek(to: time)

            // A newer seek or another track takes over
            guard self.seekGeneration == generation else { return }
            self.isSeeking = false
            guard self.player.currentItem === item else { return }

            if !finished || item.status == .failed {
                let currentTime = self.player.currentTime().seconds
                if currentTime.isFinite {
                    self.setProgressWithoutSeeking(currentTime)
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func setProgressWithoutSeeking(_ progress: TimeInterval) {
        shouldSeek = false
        self.progress = progress
        shouldSeek = true
    }

    private func setVolumeWithoutForwarding(_ volume: Float) {
        shouldForwardVolume = false
        self.volume = volume
        shouldForwardVolume = true
    }

    // MARK: - MPNowPlayingInfoCenter

    private func addRemoteCommandTargets() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.advanceForward() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.advanceBackward() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            let position = event.positionTime
            Task { @MainActor in self?.progress = position }
            return .success
        }
    }

    private func updateNowPlayingInfo(with time: CMTime? = nil) {
        let center = MPNowPlayingInfoCenter.default()
        guard let currentStream = currentStream else {
            nowPlayingTrackID = nil
            artworkTask?.cancel()
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        let currentTime = time?.seconds ?? (sonosSession == nil ? player.currentTime().seconds : progress)
        // Lets the system extrapolate the elapsed time at the right speed
        let rate = sonosSession == nil ? playbackRate : 1

        if nowPlayingTrackID == currentStream.id, var info = center.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
            center.nowPlayingInfo = info
        }
        else {
            nowPlayingTrackID = currentStream.id
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: currentStream.title,
                MPMediaItemPropertyArtist: currentStream.user.username,
                MPMediaItemPropertyPlaybackDuration: currentStream.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: rate
            ]

            loadArtwork(for: currentStream)
        }

        if sonosSession != nil {
            center.playbackState = isPlaying ? .playing : .paused
            return
        }

        switch player.timeControlStatus {
        case .paused: center.playbackState = .paused
        case .playing: center.playbackState = .playing
        case .waitingToPlayAtSpecifiedRate: center.playbackState = .interrupted
        default: center.playbackState = .unknown
        }
    }

    private func loadArtwork(for track: Track) {
        let url = track.artworkURL ?? track.user.avatarURL

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }

            // The track might have changed while the artwork was loading
            let center = MPNowPlayingInfoCenter.default()
            guard self?.nowPlayingTrackID == track.id, var info = center.nowPlayingInfo else { return }

            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            center.nowPlayingInfo = info
        }
    }

}

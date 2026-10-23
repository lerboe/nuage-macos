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

    var volume: Float = 0.5 {
        didSet {
            let clampedVolume = min(max(volume, 0), 1)
            if clampedVolume != volume {
                volume = clampedVolume
            }

            player.volume = volume
            UserDefaults.standard.set(volume, forKey: volumeKey)
        }
    }

    @ObservationIgnored private var shouldSeek = true
    var progress: TimeInterval = 0.0 {
        didSet {
            guard shouldSeek else { return }

            let duration = TimeInterval(currentStream?.duration ?? 0)
            let clampedProgress = duration > 0 ? min(max(progress, 0), duration) : max(progress, 0)
            if clampedProgress != progress {
                progress = clampedProgress
            }

            let time = CMTime(seconds: progress, preferredTimescale: 600)
            player.seek(to: time)
            updateNowPlayingInfo(with: time)
        }
    }

    private(set) var isPlaying = false

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
        // Property observers aren't called during initialization
        player.volume = volume

        let interval = CMTime(value: 1, timescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.setProgressWithoutSeeking(time.seconds)
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

    private func timeControlStatusDidChange() {
        isPlaying = (player.timeControlStatus != .paused)
        updateNowPlayingInfo()
    }

    // MARK: - Playback

    func restartPlayback() {
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
        if currentStream == newStream && player.currentItem != nil {
            currentStreamIndex = idx
            player.play()
            return
        }

        currentStreamIndex = idx
        player.replaceCurrentItem(with: nil)
        setProgressWithoutSeeking(0)

        // Cancel the loading of a previously requested track,
        // so that a slow response can't override a newer selection.
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            do {
                let asset = try await newStream.prepare()
                guard let self = self, !Task.isCancelled else { return }

                let item = AVPlayerItem(asset: asset)
                self.player.replaceCurrentItem(with: item)
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
        player.pause()
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

        if idx > 0 && player.currentTime() < CMTime(value: 15, timescale: 1) {
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

    private func setProgressWithoutSeeking(_ progress: TimeInterval) {
        shouldSeek = false
        self.progress = progress
        shouldSeek = true
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

        let currentTime = (time ?? player.currentTime()).seconds

        if nowPlayingTrackID == currentStream.id, var info = center.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            center.nowPlayingInfo = info
        }
        else {
            nowPlayingTrackID = currentStream.id
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: currentStream.title,
                MPMediaItemPropertyArtist: currentStream.user.username,
                MPMediaItemPropertyPlaybackDuration: currentStream.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime
            ]

            loadArtwork(for: currentStream)
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

//
//  StreamPlayer.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import AppKit
import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import URLImage
import SoundCloud

protocol Streamable {

    func prepare() -> AnyPublisher<AVURLAsset, Error>

}

private let volumeKey = "volume"
private let shuffleQueueKey = "shuffleQueue"
private let repeatQueueKey = "repeatQueue"

class StreamPlayer: ObservableObject {

    private var subscriptions = Set<AnyCancellable>()
    private var streamSubscription: AnyCancellable?
    private var didPlayToEndSubscription: AnyCancellable?
    private var artworkSubscription: AnyCancellable?
    private var historySubscription: AnyCancellable?
    private var timeObserver: Any?

    private(set) var player: AVPlayer

    /// The tracks in the order they were enqueued.
    @Published private(set) var queue = [Track]()

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

    @Published private(set) var currentStream: Track?

    @Published var shuffleQueue: Bool {
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

    @Published var repeatQueue: Bool {
        didSet {
            UserDefaults.standard.set(repeatQueue, forKey: repeatQueueKey)
        }
    }

    @Published var volume: Float = 0.5 {
        didSet {
            if volume > 1 { volume = 1 }
            else if volume < 0 { volume = 0 }

            player.volume = volume
            UserDefaults.standard.set(volume, forKey: volumeKey)
        }
    }

    private var shouldSeek = true
    @Published var progress: TimeInterval = 0.0 {
        didSet {
            guard shouldSeek else { return }

            let duration = TimeInterval(currentStream?.duration ?? 0)
            if progress < 0 { progress = 0 }
            else if duration > 0 && progress > duration { progress = duration }

            let time = CMTime(seconds: progress, preferredTimescale: 600)
            player.seek(to: time)
            updateNowPlayingInfo(with: time)
        }
    }

    @Published private(set) var isPlaying = false

    private var nowPlayingTrackID: String?

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
            self?.setProgressWithoutSeeking(time.seconds)
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.isPlaying = (status != .paused)
                self?.updateNowPlayingInfo()
            }
            .store(in: &subscriptions)

        // Whenever the current stream changes, add it to the SoundCloud history
        historySubscription = $currentStream
            .compactMap { $0 }
            .removeDuplicates()
            .flatMap { track in
                SoundCloud.shared.perform(.addToHistory(track))
                    .catch { error -> Empty<(), Never> in
                        print("Failed to add track to history: \(error)")
                        return Empty()
                    }
            }
            .sink { _ in }

        addRemoteCommandTargets()
    }

    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
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

        // Replacing the subscription cancels the loading of a previously requested track,
        // so that a slow response can't override a newer selection.
        streamSubscription = newStream.prepare()
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion  {
                    print("Failed to stream track: \(error)")
                }
            }, receiveValue: { [weak self] asset in
                guard let self = self else { return }

                let item = AVPlayerItem(asset: asset)

                self.player.replaceCurrentItem(with: item)
                self.player.play()

                self.didPlayToEndSubscription = NotificationCenter.default
                    .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                    .receive(on: RunLoop.main)
                    .sink { [weak self] _ in self?.advanceForward() }

                self.updateNowPlayingInfo()
            })
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
        streamSubscription = nil
        didPlayToEndSubscription = nil
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
            self?.togglePlayback()
            return .success
        }

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.advanceForward()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.advanceBackward()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.progress = event.positionTime
            return .success
        }
    }

    private func updateNowPlayingInfo(with time: CMTime? = nil) {
        let center = MPNowPlayingInfoCenter.default()
        guard let currentStream = currentStream else {
            nowPlayingTrackID = nil
            artworkSubscription = nil
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

            let url = currentStream.artworkURL ?? currentStream.user.avatarURL
            let trackID = currentStream.id
            artworkSubscription = URLImageService.shared.remoteImagePublisher(url)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in },
                      receiveValue: { [weak self] imageInfo in
                    // The track might have changed while the artwork was loading
                    guard self?.nowPlayingTrackID == trackID, var info = center.nowPlayingInfo else { return }

                    let image = NSImage(cgImage: imageInfo.cgImage, size: imageInfo.size)
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    center.nowPlayingInfo = info
                })
        }

        switch player.timeControlStatus {
        case .paused: center.playbackState = .paused
        case .playing: center.playbackState = .playing
        case .waitingToPlayAtSpecifiedRate: center.playbackState = .interrupted
        default: center.playbackState = .unknown
        }
    }

}

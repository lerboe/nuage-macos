//
//  SonosRelay.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation
import Network
import Darwin

/// Where a Sonos speaker gets the audio of a track from.
enum SonosSource: Sendable {

    /// The speaker streams the file itself.
    case file(URL)

    /// The speaker streams from this Mac, which converts the audio on the fly. Such a stream
    /// can't be seeked, so the URL takes the position to start from.
    case relay(mimeType: String, duration: TimeInterval, url: @Sendable (TimeInterval) -> URL)

}

/// A small HTTP server that serves HLS streams to Sonos speakers, which can't play them.
/// The AAC audio of fragmented MP4 segments is served as ADTS, MP3 segments are just concatenated.
actor SonosRelay {

    static let shared = SonosRelay()

    private struct Stream {
        /// Resolves a fresh playlist URL, since the signed ones expire.
        var resolvePlaylistURL: @Sendable () async throws -> URL
        /// The URL resolved during registration, used for the first request.
        var playlistURL: URL?
    }

    private var streams = [String: Stream]()
    private var streamIDs = [String]()

    /// The playback positions of the requested URLs, keyed by their path and query.
    /// A speaker that requests a URL again, e.g. after its connection dropped, continues from there.
    private var playbackPositions = [String: TimeInterval]()

    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private let queue = DispatchQueue(label: "ch.laurinbrandner.nuage.sonos-relay")

    private static let path = "/tracks/"

    // MARK: - Registration

    /// Returns the source of an HLS stream for the speaker at `speakerURL`.
    func source(playlistURL: URL, resolvePlaylistURL: @escaping @Sendable () async throws -> URL, reachableFrom speakerURL: URL) async throws -> SonosSource {
        guard let speakerHost = speakerURL.host, let address = SonosRelay.localAddress(reaching: speakerHost) else {
            throw HLSError("No network interface reaches the speaker")
        }

        // Fail early if the format can't be relayed, and tell the speaker which one it gets
        let playlist = try await HLSPlaylist.load(from: playlistURL)
        let mimeType: String
        if let initializationURL = playlist.initializationURL {
            _ = try ADTSConverter(initializationSegment: try await fetchBytes(from: initializationURL))
            mimeType = "audio/aac"
        }
        else {
            mimeType = "audio/mpeg"
        }

        let port = try await startListening()

        let id = UUID().uuidString
        streams[id] = Stream(resolvePlaylistURL: resolvePlaylistURL, playlistURL: playlistURL)
        streamIDs.append(id)
        // Only the recent tracks can still be requested
        while streamIDs.count > 20 {
            streams[streamIDs.removeFirst()] = nil
        }

        // The stream can be shorter than the track, e.g. a preview
        let duration = playlist.segments.last.map { $0.start + $0.duration } ?? 0
        return .relay(mimeType: mimeType, duration: duration) { start in
            var components = URLComponents()
            components.scheme = "http"
            components.host = address
            components.port = Int(port.rawValue)
            components.path = SonosRelay.path + id
            // Every request gets its own URL, so a repeated request can be told apart from a restart
            components.queryItems = [
                URLQueryItem(name: "start", value: String(Int(max(start, 0)))),
                URLQueryItem(name: "request", value: String(UUID().uuidString.prefix(8)))
            ]
            // The components are all valid, so this can't fail
            return components.url ?? URL(fileURLWithPath: "/")
        }
    }

    func setPlaybackPosition(_ position: TimeInterval, forStreamAt url: URL) {
        guard let key = SonosRelay.key(for: URLComponents(url: url, resolvingAgainstBaseURL: false)),
              playbackPositions[key] != nil else { return }

        playbackPositions[key] = position
    }

    private static func key(for components: URLComponents?) -> String? {
        guard let components = components else { return nil }
        return components.percentEncodedPath + "?" + (components.percentEncodedQuery ?? "")
    }

    private func nextPlaylistURL(forStreamWithID id: String) async throws -> URL? {
        guard let stream = streams[id] else { return nil }

        if let url = stream.playlistURL {
            streams[id]?.playlistURL = nil
            return url
        }

        return try await stream.resolvePlaylistURL()
    }

    // MARK: - Server

    private func startListening() async throws -> NWEndpoint.Port {
        if let port = port {
            return port
        }

        // The relay is a singleton, so the handlers can keep it
        let relay = self
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            Task { await relay.handle(connection) }
        }

        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            // The handler is replaced once it resumed the continuation
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        continuation.resume(returning: port)
                    }
                    else {
                        continuation.resume(throwing: HLSError("The relay has no port"))
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    return
                }

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .failed, .cancelled:
                        Task { await relay.listenerDidStop() }
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
        }

        self.listener = listener
        self.port = port
        return port
    }

    private func listenerDidStop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handle(_ connection: NWConnection) async {
        connection.start(queue: queue)
        defer { connection.cancel() }

        do {
            let request = try await receiveRequestHeader(on: connection)
            let requestLine = request.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
            guard requestLine.count >= 2,
                  let components = URLComponents(string: String(requestLine[1])),
                  components.path.hasPrefix(SonosRelay.path),
                  let playlistURL = try await nextPlaylistURL(forStreamWithID: String(components.path.dropFirst(SonosRelay.path.count))) else {
                try await send(Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection)
                return
            }

            var start = components.queryItems?.first { $0.name == "start" }?.value.flatMap(TimeInterval.init) ?? 0
            if let key = SonosRelay.key(for: components) {
                if let position = playbackPositions[key] {
                    start = position
                }
                else {
                    // Only the recent requests have to be remembered
                    if playbackPositions.count > 50 {
                        playbackPositions.removeAll()
                    }
                    playbackPositions[key] = start
                }
            }

            try await stream(from: playlistURL, startingAt: start, headOnly: requestLine[0] == "HEAD", on: connection)
        }
        catch {
            print("Sonos relay failed: \(error)")
        }
    }

    private func stream(from playlistURL: URL, startingAt start: TimeInterval, headOnly: Bool, on connection: NWConnection) async throws {
        let playlist = try await HLSPlaylist.load(from: playlistURL)
        let converter = try await playlist.initializationURL.asyncMap {
            try ADTSConverter(initializationSegment: try await fetchBytes(from: $0))
        }

        // The length is unknown upfront, so the end of the stream is marked by closing the connection
        let mimeType = (converter == nil) ? "audio/mpeg" : "audio/aac"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        try await send(Data(header.utf8), on: connection)
        guard !headOnly else { return }

        let firstIndex = playlist.segments.lastIndex { $0.start <= start } ?? 0
        for (index, segment) in playlist.segments.enumerated().dropFirst(firstIndex) {
            let bytes = try await fetchBytes(from: segment.url)

            if let converter = converter {
                // Start in the middle of the first segment. MP3 segments start at their beginning.
                let skippedTime = (index == firstIndex) ? max(start - segment.start, 0) : 0
                let skippedFrames = Int(skippedTime * converter.sampleRate / ADTSConverter.samplesPerFrame)
                try await send(try converter.frames(in: bytes, skipping: skippedFrames), on: connection)
            }
            else {
                try await send(Data(bytes), on: connection)
            }
        }
    }

    // MARK: - Connection

    private func receiveRequestHeader(on connection: NWConnection) async throws -> String {
        var header = Data()
        let terminator = Data("\r\n\r\n".utf8)

        while header.range(of: terminator) == nil {
            guard header.count < 16 * 1024 else { throw HLSError("The request header is too large") }

            let chunk: Data? = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    }
                    else {
                        continuation.resume(returning: (data?.isEmpty == false || !isComplete) ? data : nil)
                    }
                }
            }

            guard let chunk = chunk else { throw HLSError("The connection closed before the request was complete") }
            header.append(chunk)
        }

        return String(decoding: header, as: UTF8.self)
    }

    /// Returns once the data is handed to the network stack, which slows the stream down to the pace of the speaker.
    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                }
                else {
                    continuation.resume()
                }
            })
        }
    }

    /// Returns the IPv4 address of the interface that reaches `host`, which the speaker can connect back to.
    private static func localAddress(reaching host: String) -> String? {
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(1400).bigEndian
        guard inet_pton(AF_INET, host, &remote.sin_addr) == 1 else { return nil }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Connecting a UDP socket picks the route without sending anything
        let didConnect = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard didConnect else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didGetName = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length) == 0
            }
        }
        guard didGetName else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }

        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

}

extension Optional {

    fileprivate func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }

}

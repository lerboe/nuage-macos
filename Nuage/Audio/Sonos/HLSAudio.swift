//
//  HLSAudio.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation

struct HLSError: Error, CustomStringConvertible {

    var description: String

    init(_ description: String) {
        self.description = description
    }

}

/// The segments of an HLS stream with a fixed length (VOD).
struct HLSPlaylist: Sendable {

    struct Segment: Sendable {
        var url: URL
        var start: TimeInterval
        var duration: TimeInterval
    }

    /// The fragmented MP4 header of the segments, nil if the segments are self-contained (e.g. MP3).
    var initializationURL: URL?
    var segments: [Segment]

    static func load(from url: URL) async throws -> HLSPlaylist {
        let text = String(decoding: try await fetchBytes(from: url), as: UTF8.self)

        var initializationURL: URL?
        var segments = [Segment]()
        var segmentDuration: TimeInterval?
        var start: TimeInterval = 0
        var isMultivariant = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXT-X-STREAM-INF") {
                isMultivariant = true
            }
            else if line.hasPrefix("#EXT-X-KEY"), !line.contains("METHOD=NONE") {
                throw HLSError("Encrypted HLS streams aren't supported")
            }
            else if line.hasPrefix("#EXT-X-MAP") {
                initializationURL = attribute("URI", in: line).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
            }
            else if line.hasPrefix("#EXTINF:") {
                segmentDuration = TimeInterval(line.dropFirst("#EXTINF:".count).prefix { $0 != "," })
            }
            else if !line.hasPrefix("#"), let lineURL = URL(string: line, relativeTo: url)?.absoluteURL {
                // A multivariant playlist lists other playlists, the first one is used
                if isMultivariant {
                    return try await load(from: lineURL)
                }

                let duration = segmentDuration ?? 0
                segments.append(Segment(url: lineURL, start: start, duration: duration))
                start += duration
                segmentDuration = nil
            }
        }

        guard !segments.isEmpty else { throw HLSError("The HLS playlist has no segments") }
        return HLSPlaylist(initializationURL: initializationURL, segments: segments)
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=\"") else { return nil }

        let value = line[range.upperBound...].prefix { $0 != "\"" }
        return String(value)
    }

}

func fetchBytes(from url: URL) async throws -> [UInt8] {
    let (data, response) = try await URLSession.shared.data(from: url)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard statusCode == 200 else { throw HLSError("Loading \(url.lastPathComponent) failed with status \(statusCode)") }

    return [UInt8](data)
}

/// Converts the AAC samples of fragmented MP4 segments to ADTS, a format without a container
/// that can be streamed by just concatenating its frames.
struct ADTSConverter: Sendable {

    /// The MPEG-4 audio object type minus one, e.g. 1 for AAC LC.
    private let profile: UInt8
    private let frequencyIndex: UInt8
    private let channelConfiguration: UInt8

    let sampleRate: Double

    /// Every AAC frame holds this many samples per channel.
    static let samplesPerFrame = 1024.0

    init(initializationSegment bytes: [UInt8]) throws {
        guard let config = audioSpecificConfig(in: bytes) else {
            throw HLSError("The stream doesn't contain AAC audio")
        }

        var reader = BitReader(bytes: config)
        var objectType = try reader.read(5)
        let frequencyIndex = try reader.read(4)
        let channelConfiguration = try reader.read(4)

        // HE-AAC signals the underlying AAC type after the extension sample rate.
        // ADTS only describes the core stream, decoders find the extension themselves.
        if objectType == 5 || objectType == 29 {
            _ = try reader.read(4)
            objectType = try reader.read(5)
        }

        let sampleRates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        guard (1...4).contains(objectType),
              sampleRates.indices.contains(frequencyIndex),
              (1...7).contains(channelConfiguration) else {
            throw HLSError("The AAC configuration (type \(objectType), frequency \(frequencyIndex), channels \(channelConfiguration)) can't be described with ADTS")
        }

        self.profile = UInt8(objectType - 1)
        self.frequencyIndex = UInt8(frequencyIndex)
        self.channelConfiguration = UInt8(channelConfiguration)
        self.sampleRate = sampleRates[frequencyIndex]
    }

    /// Returns the ADTS frames of the samples in a media segment, without the first `skippedFrames`.
    func frames(in segment: [UInt8], skipping skippedFrames: Int = 0) throws -> Data {
        var frames = Data()
        var skipped = 0

        let topLevelBoxes = boxes(in: segment, from: 0, to: segment.count)
        for (index, moof) in topLevelBoxes.enumerated() where moof.type == "moof" {
            let mdat = topLevelBoxes[(index + 1)...].first { $0.type == "mdat" }

            for traf in boxes(in: segment, from: moof.contentStart, to: moof.end) where traf.type == "traf" {
                let children = boxes(in: segment, from: traf.contentStart, to: traf.end)
                guard let tfhd = children.first(where: { $0.type == "tfhd" }) else { continue }

                // Track fragment header: optional fields depend on the flags
                let tfhdFlags = segment.uint24(at: tfhd.contentStart + 1)
                var offset = tfhd.contentStart + 8
                var baseOffset = moof.start
                var defaultSampleSize = 0
                if tfhdFlags & 0x01 != 0 {
                    baseOffset = Int(truncatingIfNeeded: segment.uint64(at: offset))
                    offset += 8
                }
                if tfhdFlags & 0x02 != 0 { offset += 4 }
                if tfhdFlags & 0x08 != 0 { offset += 4 }
                if tfhdFlags & 0x10 != 0 {
                    defaultSampleSize = Int(segment.uint32(at: offset))
                }

                // Without an explicit offset, the samples follow the previous run or start the media data
                var position = mdat?.contentStart
                for trun in children where trun.type == "trun" {
                    let flags = segment.uint24(at: trun.contentStart + 1)
                    var offset = trun.contentStart + 4
                    let sampleCount = Int(segment.uint32(at: offset))
                    offset += 4

                    if flags & 0x001 != 0 {
                        position = baseOffset + Int(Int32(bitPattern: segment.uint32(at: offset)))
                        offset += 4
                    }
                    if flags & 0x004 != 0 { offset += 4 }

                    let fieldsPerSample = [0x100, 0x200, 0x400, 0x800].filter { flags & $0 != 0 }.count
                    guard var samplePosition = position,
                          offset + sampleCount * fieldsPerSample * 4 <= trun.end else {
                        throw HLSError("The MP4 fragment is malformed")
                    }

                    for _ in 0..<sampleCount {
                        if flags & 0x100 != 0 { offset += 4 }
                        var size = defaultSampleSize
                        if flags & 0x200 != 0 {
                            size = Int(segment.uint32(at: offset))
                            offset += 4
                        }
                        if flags & 0x400 != 0 { offset += 4 }
                        if flags & 0x800 != 0 { offset += 4 }

                        guard size > 0, samplePosition + size <= segment.count else {
                            throw HLSError("The MP4 fragment is malformed")
                        }

                        if skipped < skippedFrames {
                            skipped += 1
                        }
                        else {
                            frames.append(contentsOf: try header(forPayloadSize: size))
                            frames.append(contentsOf: segment[samplePosition..<samplePosition + size])
                        }
                        samplePosition += size
                    }
                    position = samplePosition
                }
            }
        }

        return frames
    }

    /// Returns the 7 byte ADTS header without checksum.
    private func header(forPayloadSize payloadSize: Int) throws -> [UInt8] {
        let length = payloadSize + 7
        guard length < 1 << 13 else { throw HLSError("The AAC frame is too large for ADTS") }

        return [
            0xFF,
            0xF1, // MPEG-4, no checksum
            (profile << 6) | (frequencyIndex << 2) | (channelConfiguration >> 2),
            ((channelConfiguration & 0x3) << 6) | UInt8((length >> 11) & 0x3),
            UInt8((length >> 3) & 0xFF),
            UInt8((length & 0x7) << 5) | 0x1F,
            0xFC
        ]
    }

}

// MARK: - MP4

private struct Box {
    var type: String
    var start: Int
    var contentStart: Int
    var end: Int
}

private func boxes(in bytes: [UInt8], from start: Int, to end: Int) -> [Box] {
    var result = [Box]()
    var offset = start

    while offset + 8 <= end {
        var size = Int(bytes.uint32(at: offset))
        let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
        var headerSize = 8

        if size == 1 {
            guard offset + 16 <= end else { break }
            size = Int(truncatingIfNeeded: bytes.uint64(at: offset + 8))
            headerSize = 16
        }
        else if size == 0 {
            size = end - offset
        }

        guard size >= headerSize, offset + size <= end else { break }

        result.append(Box(type: type, start: offset, contentStart: offset + headerSize, end: offset + size))
        offset += size
    }

    return result
}

/// Finds the AAC configuration in moov/trak/mdia/minf/stbl/stsd/mp4a/esds.
private func audioSpecificConfig(in bytes: [UInt8]) -> [UInt8]? {
    func child(_ type: String, of box: Box, skipping skippedBytes: Int = 0) -> Box? {
        return boxes(in: bytes, from: box.contentStart + skippedBytes, to: box.end).first { $0.type == type }
    }

    guard let moov = boxes(in: bytes, from: 0, to: bytes.count).first(where: { $0.type == "moov" }) else { return nil }

    for trak in boxes(in: bytes, from: moov.contentStart, to: moov.end) where trak.type == "trak" {
        // The sample description table starts with version, flags and the entry count.
        // An audio sample entry has 28 bytes of fields before its child boxes.
        guard let stbl = child("mdia", of: trak).flatMap({ child("minf", of: $0) }).flatMap({ child("stbl", of: $0) }),
              let stsd = child("stsd", of: stbl),
              let mp4a = child("mp4a", of: stsd, skipping: 8),
              let esds = child("esds", of: mp4a, skipping: 28) else { continue }

        return decoderSpecificInfo(in: bytes, from: esds.contentStart + 4, to: esds.end)
    }

    return nil
}

/// Parses the MPEG-4 descriptors ES_Descriptor > DecoderConfigDescriptor > DecoderSpecificInfo.
private func decoderSpecificInfo(in bytes: [UInt8], from start: Int, to end: Int) -> [UInt8]? {
    func descriptor(at offset: Int) -> (tag: UInt8, contentStart: Int, end: Int)? {
        guard offset < end else { return nil }

        var length = 0
        var position = offset + 1
        for _ in 0..<4 {
            guard position < end else { return nil }
            let byte = bytes[position]
            position += 1
            length = (length << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }

        guard position + length <= end else { return nil }
        return (bytes[offset], position, position + length)
    }

    guard let es = descriptor(at: start), es.tag == 0x03, es.contentStart + 3 <= es.end else { return nil }

    // Skip the ES_ID and the optional fields announced by the flags
    let flags = bytes[es.contentStart + 2]
    var offset = es.contentStart + 3
    if flags & 0x80 != 0 { offset += 2 }
    if flags & 0x40 != 0, offset < es.end { offset += 1 + Int(bytes[offset]) }
    if flags & 0x20 != 0 { offset += 2 }

    // The decoder config has 13 bytes of fields before the decoder specific info
    guard let decoderConfig = descriptor(at: offset), decoderConfig.tag == 0x04,
          let info = descriptor(at: decoderConfig.contentStart + 13), info.tag == 0x05 else { return nil }

    return Array(bytes[info.contentStart..<info.end])
}

private struct BitReader {

    var bytes: [UInt8]
    private var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func read(_ count: Int) throws -> Int {
        var value = 0
        for _ in 0..<count {
            guard position / 8 < bytes.count else { throw HLSError("The AAC configuration is truncated") }

            let bit = (bytes[position / 8] >> (7 - UInt8(position % 8))) & 1
            value = (value << 1) | Int(bit)
            position += 1
        }

        return value
    }

}

extension Array where Element == UInt8 {

    // Out of bounds reads return 0, the box sizes are validated beforehand

    fileprivate func uint24(at offset: Int) -> Int {
        guard offset + 3 <= count else { return 0 }
        return (Int(self[offset]) << 16) | (Int(self[offset + 1]) << 8) | Int(self[offset + 2])
    }

    fileprivate func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    fileprivate func uint64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return self[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

}

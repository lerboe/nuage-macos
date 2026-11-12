//
//  SonosClient.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation

/// A group of Sonos speakers playing in sync, possibly consisting of a single speaker.
struct SonosGroup: Identifiable, Hashable, Sendable {

    /// The UUID of the group's coordinator, e.g. `RINCON_000E58...`.
    var id: String
    var name: String

    /// The base URL of the coordinator, which handles the transport of the whole group.
    var coordinatorURL: URL

}

enum SonosTransportState: String, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case noMedia = "NO_MEDIA_PRESENT"
}

struct SonosPositionInfo: Sendable {
    var position: TimeInterval
    /// 0 if the speaker doesn't know the duration, e.g. of a relayed stream.
    var duration: TimeInterval
    var trackURI: String
}

struct SonosError: Error, CustomStringConvertible {

    var action: String
    var statusCode: Int
    /// The UPnP error code, e.g. 701 (transition not available) or 714 (illegal MIME type).
    var upnpErrorCode: String?

    var description: String {
        return "Sonos \(action) failed with status \(statusCode), UPnP error \(upnpErrorCode ?? "unknown")"
    }

}

/// A minimal client for the local UPnP (SOAP) API of a Sonos speaker.
struct SonosClient: Sendable {

    var baseURL: URL

    private enum Service {
        case avTransport
        case groupRenderingControl
        case zoneGroupTopology

        var controlPath: String {
            switch self {
            case .avTransport: return "/MediaRenderer/AVTransport/Control"
            case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Control"
            case .zoneGroupTopology: return "/ZoneGroupTopology/Control"
            }
        }

        var urn: String {
            switch self {
            case .avTransport: return "urn:schemas-upnp-org:service:AVTransport:1"
            case .groupRenderingControl: return "urn:schemas-upnp-org:service:GroupRenderingControl:1"
            case .zoneGroupTopology: return "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
            }
        }
    }

    // MARK: - Transport

    func setTransportURI(_ uri: URL, metadata: String) async throws {
        try await perform("SetAVTransportURI", on: .avTransport, arguments: [
            ("InstanceID", "0"),
            ("CurrentURI", uri.absoluteString),
            ("CurrentURIMetaData", metadata)
        ])
    }

    func play() async throws {
        try await perform("Play", on: .avTransport, arguments: [("InstanceID", "0"), ("Speed", "1")])
    }

    func pause() async throws {
        try await perform("Pause", on: .avTransport, arguments: [("InstanceID", "0")])
    }

    func stop() async throws {
        try await perform("Stop", on: .avTransport, arguments: [("InstanceID", "0")])
    }

    func seek(to position: TimeInterval) async throws {
        try await perform("Seek", on: .avTransport, arguments: [
            ("InstanceID", "0"),
            ("Unit", "REL_TIME"),
            ("Target", format(position: position))
        ])
    }

    func transportState() async throws -> SonosTransportState? {
        let response = try await perform("GetTransportInfo", on: .avTransport, arguments: [("InstanceID", "0")])
        return response["CurrentTransportState"].flatMap(SonosTransportState.init(rawValue:))
    }

    func positionInfo() async throws -> SonosPositionInfo {
        let response = try await perform("GetPositionInfo", on: .avTransport, arguments: [("InstanceID", "0")])
        return SonosPositionInfo(position: parse(position: response["RelTime"]),
                                 duration: parse(position: response["TrackDuration"]),
                                 trackURI: response["TrackURI"] ?? "")
    }

    // MARK: - Volume

    /// The volume of the whole group, between 0 and 100.
    func groupVolume() async throws -> Int {
        let response = try await perform("GetGroupVolume", on: .groupRenderingControl, arguments: [("InstanceID", "0")])
        return response["CurrentVolume"].flatMap { Int($0) } ?? 0
    }

    func setGroupVolume(_ volume: Int) async throws {
        try await perform("SetGroupVolume", on: .groupRenderingControl, arguments: [
            ("InstanceID", "0"),
            ("DesiredVolume", String(min(max(volume, 0), 100)))
        ])
    }

    // MARK: - Topology

    /// Returns all groups of the household this speaker belongs to.
    func zoneGroups() async throws -> [SonosGroup] {
        let response = try await perform("GetZoneGroupState", on: .zoneGroupTopology, arguments: [])
        // The state is an XML document itself, which has already been unescaped by the parser
        guard let state = response["ZoneGroupState"]?.data(using: .utf8) else { return [] }

        let delegate = ZoneGroupParser()
        let parser = XMLParser(data: state)
        parser.delegate = delegate
        parser.parse()

        return delegate.groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - SOAP

    @discardableResult
    private func perform(_ action: String, on service: Service, arguments: [(String, String)]) async throws -> [String: String] {
        let body = arguments.map { "<\($0)>\($1.xmlEscaped)</\($0)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(service.urn)">\(body)</u:\(action)></s:Body>\
        </s:Envelope>
        """

        var request = URLRequest(url: baseURL.appendingPathComponent(service.controlPath), timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let values = XMLValueParser.values(in: data)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw SonosError(action: action, statusCode: statusCode, upnpErrorCode: values["errorCode"])
        }

        return values
    }

    // MARK: - Metadata

    /// Returns the DIDL-Lite metadata that makes the speaker show the track's details.
    static func metadata(title: String, artist: String, artworkURL: URL?, duration: TimeInterval, uri: URL, mimeType: String) -> String {
        let artwork = artworkURL.map { "<upnp:albumArtURI>\($0.absoluteString.xmlEscaped)</upnp:albumArtURI>" } ?? ""

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="-1" parentID="-1" restricted="true">\
        <res protocolInfo="http-get:*:\(mimeType):*" duration="\(format(position: duration))">\(uri.absoluteString.xmlEscaped)</res>\
        <dc:title>\(title.xmlEscaped)</dc:title>\
        <dc:creator>\(artist.xmlEscaped)</dc:creator>\
        \(artwork)\
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        </item></DIDL-Lite>
        """
    }

}

// MARK: - Helpers

/// Formats a position as `H:MM:SS`, which is what UPnP expects.
private func format(position: TimeInterval) -> String {
    let seconds = max(Int(position), 0)
    return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
}

/// Parses a position formatted as `H:MM:SS`. Returns 0 for values like `NOT_IMPLEMENTED`.
private func parse(position: String?) -> TimeInterval {
    guard let components = position?.split(separator: ":").map({ TimeInterval($0) }),
          components.count == 3,
          let hours = components[0], let minutes = components[1], let seconds = components[2] else { return 0 }

    return hours * 3600 + minutes * 60 + seconds
}

extension String {

    fileprivate var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

}

/// Collects the text of the leaf elements of a SOAP response, keyed by their name.
private final class XMLValueParser: NSObject, XMLParserDelegate {

    private var values = [String: String]()
    private var text = ""

    static func values(in data: Data) -> [String: String] {
        let delegate = XMLValueParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Strip namespace prefixes like `u:`
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if values[name] == nil {
            values[name] = text
        }
        text = ""
    }

}

/// Parses the groups out of the `ZoneGroupState` document.
private final class ZoneGroupParser: NSObject, XMLParserDelegate {

    private struct Member {
        var uuid: String
        var name: String
        var location: URL
        var isInvisible: Bool
    }

    private(set) var groups = [SonosGroup]()

    private var coordinator: String?
    private var members = [Member]()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "ZoneGroup":
            coordinator = attributeDict["Coordinator"]
            members = []
        case "ZoneGroupMember":
            // Home theater satellites are nested `Satellite` elements and are skipped
            guard let uuid = attributeDict["UUID"],
                  let name = attributeDict["ZoneName"],
                  let location = attributeDict["Location"].flatMap(URL.init(string:)) else { return }

            members.append(Member(uuid: uuid, name: name, location: location, isInvisible: attributeDict["Invisible"] == "1"))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "ZoneGroup",
              let coordinator = members.first(where: { $0.uuid == coordinator }),
              var components = URLComponents(url: coordinator.location, resolvingAgainstBaseURL: false) else { return }

        // Invisible members are e.g. Boosts, Bridges or stereo pair partners
        var names = [coordinator.name]
        for member in members where !member.isInvisible && !names.contains(member.name) {
            names.append(member.name)
        }
        guard !coordinator.isInvisible || names.count > 1 else { return }

        components.path = ""
        components.query = nil
        guard let baseURL = components.url else { return }

        let name = names.count > 1 ? "\(names[0]) + \(names.count - 1)" : names[0]
        groups.append(SonosGroup(id: coordinator.uuid, name: name, coordinatorURL: baseURL))
    }

}

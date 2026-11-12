//
//  SonosDiscovery.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation
import Darwin

enum SonosDiscovery {

    /// Searches the local network for Sonos speakers and returns the groups of their household.
    static func groups(timeout: TimeInterval = 2) async throws -> [SonosGroup] {
        let baseURLs = try await Task.detached {
            try searchSpeakers(timeout: timeout)
        }.value

        // Every speaker knows the topology of the whole household
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await SonosClient(baseURL: baseURL).zoneGroups()
            }
            catch {
                lastError = error
            }
        }

        if let lastError = lastError {
            throw lastError
        }
        return []
    }

    /// Sends an SSDP search and collects the base URLs (e.g. `http://192.168.1.10:1400`) of the speakers that respond.
    private static func searchSpeakers(timeout: TimeInterval) throws -> Set<URL> {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }

        // Wake up regularly so the deadline is respected
        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        address.sin_addr.s_addr = inet_addr("239.255.255.250")

        let message = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 1",
            "ST: urn:schemas-upnp-org:device:ZonePlayer:1",
            "",
            ""
        ].joined(separator: "\r\n")

        // UDP is unreliable, so the search is sent twice
        var sendError: Int32?
        for _ in 0..<2 {
            let sent = message.withCString { pointer in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, pointer, strlen(pointer), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent < 0 {
                sendError = errno
            }
        }
        // This happens e.g. if the user denied access to the local network
        if let sendError = sendError {
            throw POSIXError(POSIXErrorCode(rawValue: sendError) ?? .EIO)
        }

        var baseURLs = Set<URL>()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { continue }

            let response = String(decoding: buffer[..<count], as: UTF8.self)
            guard response.contains("ZonePlayer"),
                  let location = header("LOCATION", in: response),
                  var components = URLComponents(string: location) else { continue }

            components.path = ""
            components.query = nil
            if let url = components.url {
                baseURLs.insert(url)
            }
        }

        return baseURLs
    }

    private static func header(_ name: String, in response: String) -> String? {
        let prefix = name.lowercased() + ":"
        for line in response.components(separatedBy: "\r\n") where line.lowercased().hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

}

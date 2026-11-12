//
//  SonosBrowser.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation
import Network
import Observation
import dnssd

/// Caches the Sonos groups found on the local network. They are searched when Sonos is enabled
/// and when the user asks for it, not every time the speaker list is opened.
@MainActor
@Observable
final class SonosBrowser {

    private(set) var groups = [SonosGroup]()
    private(set) var isSearching = false
    private(set) var error: Error?

    @ObservationIgnored private var accessObserver: NWBrowser?

    /// Searches for speakers. If none are found, e.g. because the user is just being asked
    /// for local network access, the search is repeated once access is granted.
    func start() async {
        await search()

        if error != nil || groups.isEmpty {
            searchWhenLocalNetworkAccessIsGranted()
        }
    }

    func stop() {
        accessObserver?.cancel()
        accessObserver = nil
    }

    func search() async {
        guard !isSearching else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            groups = try await SonosDiscovery.groups()
            error = nil
        }
        catch {
            print("Failed to discover Sonos speakers: \(error)")
            self.error = error
        }
    }

    /// There's no API for the local network access, see TN3179. But a Bonjour browser waits with
    /// `kDNSServiceErr_PolicyDenied` without access and becomes ready as soon as it's granted.
    private func searchWhenLocalNetworkAccessIsGranted() {
        stop()

        let browser = NWBrowser(for: .bonjour(type: "_sonos._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self = self, let browser = browser, self.accessObserver === browser else { return }

                switch state {
                case .ready:
                    // Only search once, so that a household without Sonos speakers isn't searched over and over
                    self.stop()
                    Task { await self.search() }
                case .waiting(.dns(let code)) where Int(code) == kDNSServiceErr_PolicyDenied:
                    // Keep waiting, the user might still allow access, also later in System Settings
                    break
                case .failed(let error):
                    print("Failed to observe local network access: \(error)")
                    self.stop()
                default:
                    break
                }
            }
        }

        accessObserver = browser
        browser.start(queue: .main)
    }

}

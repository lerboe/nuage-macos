//
//  SonosBrowser.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import Foundation
import Observation

/// Caches the Sonos groups found on the local network. They are searched at launch
/// and when the user asks for it, not every time the speaker list is opened.
@MainActor
@Observable
final class SonosBrowser {

    private(set) var groups = [SonosGroup]()
    private(set) var isSearching = false
    private(set) var error: Error?

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

}

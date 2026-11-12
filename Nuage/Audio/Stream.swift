//
//  Stream.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import AVFoundation
import SoundCloud

struct NoStreamError: Error {}

extension Track: Streamable {

    @MainActor
    func prepare() async throws -> AVURLAsset {
        return AVURLAsset(url: try await audioFileURL())
    }

    /// Resolves the URL of the audio file, which expires after a while.
    @MainActor
    func audioFileURL() async throws -> URL {
        guard let url = streamURL else { throw NoStreamError() }

        return try await SoundCloud.shared.get(.audioFile(url))
    }

}

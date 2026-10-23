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
        guard let url = streamURL else { throw NoStreamError() }

        let audioFileURL = try await SoundCloud.shared.get(.audioFile(url))
        return AVURLAsset(url: audioFileURL)
    }

}

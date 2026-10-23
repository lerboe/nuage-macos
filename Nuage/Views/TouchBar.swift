//
//  TouchBar.swift
//  Nuage
//
//  Created by Laurin Brandner on 09.07.23.
//

import SwiftUI
import SoundCloud

struct TouchBar: View {
    
    @EnvironmentObject private var player: StreamPlayer
    
    var body: some View {
        if let track = player.currentStream {
            let font = Font.system(size: 12)
                .monospacedDigit()
            HStack {
                VStack(alignment: .leading) {
                    Text(track.user.username)
                        .bold()
                        .lineLimit(1)
                        .font(font)
                    Text(track.title)
                        .lineLimit(1)
                        .font(font)
                        .truncationMode(.tail)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 200)
                progressSlider(for: track)
            }
        }
    }
    
    @ViewBuilder private func progressSlider(for track: Track) -> some View {
        let duration = TimeInterval(track.duration)
        let font = Font.system(size: 14).monospacedDigit()
        
        WaveformSlider(url: track.waveformURL, value: $player.progress, in: 0...duration, minValueLabel: { progress in
            Text(format(time: progress))
                .font(font)
                .frame(width: 70, alignment: .trailing)
        }, maxValueLabel: { _ in
            Text(format(time: duration))
                .font(font)
                .frame(width: 70, alignment: .leading)
        }, knobColor: Color(hex: 0x1A1A1A), knobBorderColor: Color(hex: 0x5A5A5A))
        .frame(minWidth: 440)
        .foregroundColor(.white)
    }
    
}

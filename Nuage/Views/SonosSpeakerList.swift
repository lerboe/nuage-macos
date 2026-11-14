//
//  SonosSpeakerList.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import SwiftUI

/// Lets the user choose whether to play on this Mac or on a Sonos group.
struct SonosSpeakerList: View {

    @Environment(StreamPlayer.self) private var player
    @Environment(SonosBrowser.self) private var browser

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Play On")
                    .font(.headline)
                Spacer()
                if browser.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                else {
                    Button(action: { Task { await browser.search() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .focusable(false)
                    .buttonStyle(.borderless)
                    .help("Search Again")
                }
            }
            .frame(height: 20)
            .padding(.bottom, 4)

            row(title: "This Mac", systemImage: "laptopcomputer", isSelected: player.sonosGroup == nil) {
                player.playOnThisMac()
            }

            ForEach(browser.groups) { group in
                row(title: group.name, systemImage: "hifispeaker.fill", isSelected: player.sonosGroup?.id == group.id) {
                    player.play(on: group)
                }
            }

            if !browser.isSearching && browser.groups.isEmpty {
                Text(browser.error == nil ? "No Sonos speakers found" : "Couldn't search the local network")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(width: 240)
    }

    @ViewBuilder private func row(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> ()) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        // Otherwise the popover focuses its first button, which draws a focus ring when it opens
        .focusable(false)
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

}

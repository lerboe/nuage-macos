//
//  SonosSpeakerList.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.11.26.
//

import SwiftUI

/// Lets the user choose whether to play on this Mac or on a Sonos group.
struct SonosSpeakerList: View {

    @State private var groups = [SonosGroup]()
    @State private var isSearching = false
    @State private var error: Error?

    @Environment(StreamPlayer.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Play On")
                    .font(.headline)
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                else {
                    Button(action: { Task { await search() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Search Again")
                }
            }
            .frame(height: 20)
            .padding(.bottom, 4)

            row(title: "This Mac", systemImage: "laptopcomputer", isSelected: player.sonosGroup == nil) {
                player.playOnThisMac()
            }

            ForEach(groups) { group in
                row(title: group.name, systemImage: "hifispeaker.fill", isSelected: player.sonosGroup?.id == group.id) {
                    player.play(on: group)
                }
            }

            if !isSearching && groups.isEmpty {
                Text(error == nil ? "No Sonos speakers found" : "Couldn't search the local network")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(width: 240)
        .task { await search() }
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
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func search() async {
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

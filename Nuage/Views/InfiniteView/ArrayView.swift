//
//  ArrayView.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI

struct ArrayView<ID, Element: Decodable&Identifiable, ContentView: View>: View {

    @State private var ids: [ID]?
    @State private var elements = [Element]()

    /// The range of `ids` whose elements are loaded next.
    @State private var elementRange = 0..<16

    /// Setting it triggers loading the elements in that range.
    @State private var requestedRange: Range<Int>?

    private var loadIDs: () async throws -> [ID]
    private var loadElements: ([ID]) async throws -> [Element]

    private var content: ([Element], @escaping () -> ()) -> ContentView

    var body: some View {
        Group {
            if ids?.isEmpty ?? false {
                Text("Empty")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            else if elements.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                content(elements, getNextPage)
            }
        }
        .task {
            // Don't reload when the view reappears
            guard ids == nil else { return }

            do {
                ids = try await loadIDs()
            }
            catch {
                // The task is cancelled when the view disappears and restarted when it reappears
                guard !Task.isCancelled else { return }

                print("Failed to load ids: \(error)")
                ids = []
            }
            getNextPage()
        }
        .task(id: requestedRange) {
            // Skip ranges that are already loaded, e.g. when the view reappears
            guard let ids = ids,
                  let range = requestedRange,
                  range.lowerBound == elementRange.lowerBound else { return }

            do {
                let page = try await loadElements(Array(ids[range]))

                // A page can contain fewer elements than requested (e.g. deleted tracks),
                // so `range.lowerBound` isn't necessarily a valid index of `elements`.
                elements.append(contentsOf: page)
                elementRange = range.upperBound..<min(ids.count, range.upperBound+min(range.count*2, 50))

                // No row would appear to request more elements
                if page.isEmpty {
                    getNextPage()
                }
            }
            catch {
                guard !Task.isCancelled else { return }
                print("Failed to load elements: \(error)")
            }
        }
    }

    init(loadIDs: @escaping () async throws -> [ID],
         loadElements: @escaping ([ID]) async throws -> [Element],
         @ViewBuilder content: @escaping ([Element], @escaping () -> ()) -> ContentView) {
        self.loadIDs = loadIDs
        self.loadElements = loadElements
        self.content = content
    }

    /// Requests the next range of elements. Calls while that range is loading are ignored.
    private func getNextPage() {
        guard let ids = ids else { return }

        let range = elementRange.clamped(to: 0..<ids.count)
        guard !range.isEmpty else { return }

        requestedRange = range
    }

}

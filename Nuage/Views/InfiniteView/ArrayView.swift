//
//  ArrayView.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI

/// The number of elements loaded first.
private let firstPageSize = 16

struct ArrayView<ID: Equatable, Element: Decodable&Identifiable, ContentView: View>: View {

    @State private var ids: [ID]?
    @State private var elements = [Element]()

    /// The range of `ids` whose elements are loaded next.
    @State private var elementRange = 0..<firstPageSize

    /// The number of `elements` loaded with the ids, which are replaced when they are refreshed.
    @State private var firstPageCount = 0

    /// Whether the ids were loaded from the network, rather than only from the cache.
    @State private var didRefresh = false

    /// Setting it triggers loading the elements in that range.
    @State private var requestedRange: Range<Int>?

    private var loadIDs: () async throws -> [ID]
    private var loadElements: ([ID]) async throws -> [Element]

    private var content: ([Element], @escaping () -> ()) -> ContentView

    @Environment(\.search) private var search: Search?

    var body: some View {
        Group {
            let isEmpty = ids?.isEmpty ?? false
            // While searching, the content still shows the search results
            if isEmpty && search == nil {
                Text("Empty")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            else if elements.isEmpty && !isEmpty {
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
            guard !didRefresh else { return }

            // Show the cached elements until the fresh ones are loaded
            if ids == nil, let page = try? await cached(loadFirstPage) {
                show(page.elements, of: page.ids)
            }

            do {
                let page = try await refreshed(loadFirstPage)
                if page.ids == ids {
                    // Keep the elements loaded since, so that the user's scroll position isn't lost
                    elements.replaceSubrange(0..<firstPageCount, with: page.elements)
                    firstPageCount = page.elements.count
                }
                else {
                    show(page.elements, of: page.ids)
                }
            }
            catch {
                // The task is cancelled when the view disappears and restarted when it reappears
                guard !Task.isCancelled else { return }

                print("Failed to load ids: \(error)")
                // Keep showing the cached elements, if there are any
                if ids == nil {
                    ids = []
                }
            }
            didRefresh = true
        }
        .task(id: requestedRange) {
            // Skip ranges that are already loaded, e.g. when the view reappears
            guard let ids = ids,
                  let range = requestedRange,
                  range.lowerBound == elementRange.lowerBound else { return }

            do {
                let page = try await loadElements(Array(ids[range]))

                // The ids were replaced by fresh ones in the meantime
                guard self.ids == ids else { return }

                // A page can contain fewer elements than requested (e.g. deleted tracks),
                // so `range.lowerBound` isn't necessarily a valid index of `elements`.
                elements.append(contentsOf: page)
                elementRange = nextRange(after: range, in: ids)

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

    /// Loads the ids and the elements of the first ones.
    private func loadFirstPage() async throws -> (ids: [ID], elements: [Element]) {
        let ids = try await loadIDs()
        let range = 0..<min(ids.count, firstPageSize)
        let elements = range.isEmpty ? [] : try await loadElements(Array(ids[range]))

        return (ids, elements)
    }

    /// Replaces the content by `elements`, the ones of the first ids.
    private func show(_ elements: [Element], of ids: [ID]) {
        let range = 0..<min(ids.count, firstPageSize)

        self.ids = ids
        self.elements = elements
        firstPageCount = elements.count
        elementRange = nextRange(after: range, in: ids)
        // Cancels loading a range of the previous ids
        requestedRange = nil

        // No row would appear to request more elements
        if elements.isEmpty {
            getNextPage()
        }
    }

    private func nextRange(after range: Range<Int>, in ids: [ID]) -> Range<Int> {
        return range.upperBound..<min(ids.count, range.upperBound+min(range.count*2, 50))
    }

    /// Requests the next range of elements. Calls while that range is loading are ignored.
    private func getNextPage() {
        guard let ids = ids else { return }

        let range = elementRange.clamped(to: 0..<ids.count)
        guard !range.isEmpty else { return }

        requestedRange = range
    }

}

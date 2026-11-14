//
//  PageView.swift
//  Nuage
//
//  Created by Laurin Brandner on 03.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

struct PageView<Element: Decodable&Identifiable, ContentView: View>: View {

    var elements: [Element] {
        return pages?.map { $0.collection }
            .reduce([], +) ?? []
    }
    @State private var pages: [Page<Element>]?

    /// Whether the first page was loaded from the network, rather than only from the cache.
    @State private var didRefresh = false

    /// The number of pages that should be loaded. Increasing it triggers loading the next page.
    @State private var requestedPageCount = 1

    private var firstPage: () async throws -> Page<Element>

    private var content: ([Element], @escaping () -> ()) -> ContentView

    @Environment(\.search) private var search: Search?

    var body: some View {
        Group {
            if pages != nil {
                // While searching, the content still shows the search results
                if elements.isEmpty && search == nil {
                    Text("Empty")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                else {
                    content(elements, getNextPage)
                }
            }
            else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Don't reload (and thereby lose all loaded pages) when the view reappears
            guard !didRefresh else { return }

            // Show the cached page until the fresh one is loaded
            if pages == nil, let page = try? await cached(firstPage) {
                pages = [page]
            }

            do {
                refresh(with: try await refreshed(firstPage))
            }
            catch {
                // The task is cancelled when the view disappears and restarted when it reappears
                guard !Task.isCancelled else { return }

                print("Failed to load page: \(error)")
                // Keep showing the cached page, if there is one
                if pages == nil {
                    pages = []
                }
            }
            didRefresh = true
        }
        .task(id: requestedPageCount) {
            guard let pages = pages,
                  requestedPageCount > pages.count,
                  let lastPage = pages.last,
                  lastPage.next != nil else { return }

            do {
                let page = try await SoundCloud.shared.get(next: lastPage)

                // The pages were replaced by fresh ones in the meantime
                guard self.pages?.last?.next == lastPage.next else { return }
                self.pages?.append(page)
            }
            catch {
                guard !Task.isCancelled else { return }
                print("Failed to load next page: \(error)")
            }
        }
    }

    init(firstPage: @escaping () async throws -> Page<Element>,
         @ViewBuilder content: @escaping ([Element], @escaping () -> ()) -> ContentView) {
        self.firstPage = firstPage
        self.content = content
    }

    /// Replaces the first page by the fresh `page`. If it contains the same elements,
    /// the following pages are kept, so that the user's scroll position isn't lost.
    private func refresh(with page: Page<Element>) {
        if var pages, let first = pages.first, first.collection.map(\.id) == page.collection.map(\.id) {
            pages[0] = page
            self.pages = pages
        }
        else {
            pages = [page]
            requestedPageCount = 1
        }
    }

    /// Requests the page after the last loaded one. Calls while that page is loading are ignored.
    private func getNextPage() {
        guard let pages = pages, pages.last?.next != nil else { return }
        requestedPageCount = max(requestedPageCount, pages.count + 1)
    }

}

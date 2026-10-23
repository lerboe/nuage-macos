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

    /// The number of pages that should be loaded. Increasing it triggers loading the next page.
    @State private var requestedPageCount = 1

    private var firstPage: () async throws -> Page<Element>

    private var content: ([Element], @escaping () -> ()) -> ContentView

    var body: some View {
        Group {
            if pages != nil {
                if elements.isEmpty {
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
            guard pages == nil else { return }

            do {
                pages = [try await firstPage()]
            }
            catch {
                // The task is cancelled when the view disappears and restarted when it reappears
                guard !Task.isCancelled else { return }

                print("Failed to load page: \(error)")
                pages = []
            }
        }
        .task(id: requestedPageCount) {
            guard let pages = pages,
                  requestedPageCount > pages.count,
                  let lastPage = pages.last,
                  lastPage.next != nil else { return }

            do {
                let page = try await SoundCloud.shared.get(next: lastPage)
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

    /// Requests the page after the last loaded one. Calls while that page is loading are ignored.
    private func getNextPage() {
        guard let pages = pages, pages.last?.next != nil else { return }
        requestedPageCount = max(requestedPageCount, pages.count + 1)
    }

}

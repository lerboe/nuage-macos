//
//  PageView.swift
//  Nuage
//
//  Created by Laurin Brandner on 03.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import Combine
import SwiftUI
import SoundCloud

private let initialPageSubscription = -1

struct PageView<Element: Decodable&Identifiable, ContentView: View>: View {
    
    var elements: [Element] {
        return pages?.map { $0.collection }
            .reduce([], +) ?? []
    }
    @State private var pages: [Page<Element>]?
    
    private var publisher: AnyPublisher<Page<Element>, Error>
    @State private var subscriptions = [Int: AnyCancellable]()
    
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
        .onAppear {
            // Don't reload (and thereby lose all loaded pages) when the view reappears
            guard pages == nil && subscriptions[initialPageSubscription] == nil else { return }
            
            publisher.receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case .failure(_) = completion {
                        pages = []
                    }
                }, receiveValue: { page in
                    pages = [page]
                })
                .store(in: &subscriptions, key: initialPageSubscription)
        }
    }
    
    init(publisher: AnyPublisher<Page<Element>, Error>,
         @ViewBuilder content: @escaping ([Element], @escaping () -> ()) -> ContentView) {
        self.publisher = publisher
        self.content = content
    }
    
    private func getNextPage() {
        // Key the request by the number of loaded pages, so that a page with no elements doesn't block the following ones
        guard let pages = pages,
              let lastPage = pages.last,
              lastPage.next != nil,
              subscriptions[pages.count] == nil else { return }

        SoundCloud.shared.get(next: lastPage)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { page in
                self.pages?.append(page)
            })
            .store(in: &subscriptions, key: pages.count)
    }
    
}

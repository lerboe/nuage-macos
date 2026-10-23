//
//  ArrayView.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import Combine
import SwiftUI

private let idSubcription = -1

struct ArrayView<ID, Element: Decodable&Identifiable, ContentView: View>: View {
    
    @State private var ids: [ID]?
    @State private var elements = [Element]()
    @State private var elementRange = 0..<16
    
    private var arrayPublisher: AnyPublisher<[ID], Error>
    private var pagePublisher: ([ID]) -> AnyPublisher<[Element], Error>
    @State private var subscriptions = [Int: AnyCancellable]()
    
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
        .onAppear {
            // Don't reload when the view reappears
            guard ids == nil && subscriptions[idSubcription] == nil else { return }
            
            arrayPublisher.receive(on: RunLoop.main)
                .replaceError(with: [])
                .sink { elementIDs in
                    ids = elementIDs
                    getNextPage()
                }
                .store(in: &subscriptions, key: idSubcription)
        }
    }
    
    init(arrayPublisher: AnyPublisher<[ID], Error>,
         pagePublisher: @escaping ([ID]) -> AnyPublisher<[Element], Error>,
         @ViewBuilder content: @escaping ([Element], @escaping () -> ()) -> ContentView) {
        self.arrayPublisher = arrayPublisher
        self.pagePublisher = pagePublisher
        self.content = content
    }
    
    private func getNextPage() {
        guard let ids = ids else { return }
        let range = elementRange.clamped(to: 0..<ids.count)
        guard !range.isEmpty, subscriptions[range.lowerBound] == nil else { return }
        
        let page = Array(ids[range])
        
        pagePublisher(page)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { page in
                // A page can contain fewer elements than requested (e.g. deleted tracks),
                // so `range.startIndex` isn't necessarily a valid index of `elements`.
                elements.append(contentsOf: page)
                elementRange = range.endIndex..<min(ids.count, range.endIndex+min(range.count*2, 50))
            })
            .store(in: &subscriptions, key: range.lowerBound)
    }
    
}

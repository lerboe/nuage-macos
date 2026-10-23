//
//  InfiniteGrid.swift
//  Nuage
//
//  Created by Laurin Brandner on 05.02.21.
//

import SwiftUI
import GridStack

struct InfiniteGrid<Element: Decodable&Identifiable&Filterable&Hashable, Item: View>: View {
    
    private var publisher: InfinitePublisher<Element>
    private var item: ([Element], Int) -> Item
    @State private var filter = ""
    @State private var isSearching = false
    
    @EnvironmentObject private var commands: CommandSubject
    
    var body: some View {
        if case let .page(publisher) = publisher {
            PageView(publisher: publisher, content: grid)
        }
        else if case let .array(arrayPublisher, pagePublisher) = publisher {
            ArrayView(arrayPublisher: arrayPublisher, pagePublisher: pagePublisher, content: grid)
        }
    }
    
    @ViewBuilder func grid(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
        let displayedElements = (filter.count > 0) ? elements.filter { $0.contains(filter) } : elements
        
        VStack {
            if isSearching {
                TextField("Filter", text: $filter)
                    .onChange(of: filter) {
                        getNextPage()
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .introspectTextField { $0.becomeFirstResponder() }
                    .onExitCommand(perform: stopFiltering)
            }
            
            GridStack(minCellWidth: 100, spacing: 20, numItems: displayedElements.count, alignment: .leading) { idx, width in
                item(displayedElements, idx)
                    .id(idx)
                    .onAppear {
                    if idx == elements.count/2 {
                        getNextPage()
                    }
                }
            }
            .onReceive(commands.filter) { withAnimation { isSearching = true } }
            .onExitCommand(perform: stopFiltering)
        }
    }
    
    init(publisher: InfinitePublisher<Element>, @ViewBuilder item: @escaping ([Element], Int) -> Item) {
        self.publisher = publisher
        self.item = item
    }
    
    private func stopFiltering() {
        withAnimation {
            isSearching = false
            filter = ""
        }
    }
    
}

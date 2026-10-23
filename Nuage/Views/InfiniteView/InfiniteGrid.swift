//
//  InfiniteGrid.swift
//  Nuage
//
//  Created by Laurin Brandner on 05.02.21.
//

import SwiftUI
import GridStack

struct InfiniteGrid<Element: Decodable&Identifiable&Filterable&Hashable, Item: View>: View {
    
    private var source: InfiniteSource<Element>
    private var item: ([Element], Int) -> Item
    @State private var filter = ""
    @State private var isSearching = false
    
    @Environment(MenuCommands.self) private var commands
    
    var body: some View {
        switch source {
        case .page(let firstPage):
            PageView(firstPage: firstPage, content: grid)
        case .array(let loadIDs, let loadElements):
            ArrayView(loadIDs: loadIDs, loadElements: loadElements, content: grid)
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
            .onChange(of: commands.filterRequests) { withAnimation { isSearching = true } }
            .onExitCommand(perform: stopFiltering)
        }
    }
    
    init(source: InfiniteSource<Element>, @ViewBuilder item: @escaping ([Element], Int) -> Item) {
        self.source = source
        self.item = item
    }
    
    private func stopFiltering() {
        withAnimation {
            isSearching = false
            filter = ""
        }
    }
    
}

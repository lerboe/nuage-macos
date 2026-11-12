//
//  InfiniteGrid.swift
//  Nuage
//
//  Created by Laurin Brandner on 05.02.21.
//

import SwiftUI

struct InfiniteGrid<Element: Decodable&Identifiable&Filterable&Hashable, Item: View>: View {

    private var source: InfiniteSource<Element>
    private var item: ([Element], Int) -> Item

    @Environment(\.search) private var search: Search?

    var body: some View {
        switch source {
        case .page(let firstPage):
            PageView(firstPage: firstPage, content: grid)
        case .array(let loadIDs, let loadElements):
            ArrayView(loadIDs: loadIDs, loadElements: loadElements, content: grid)
        }
    }

    @ViewBuilder func grid(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
        let displayedElements = search.map { search in elements.filter { $0.contains(search.query) } } ?? elements

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The section of the main view is left out if nothing in it matches
                if let search, !displayedElements.isEmpty {
                    SearchSectionHeader(title: search.scope)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 20)], alignment: .leading, spacing: 20) {
                    ForEach(0..<displayedElements.count, id: \.self) { idx in
                        item(displayedElements, idx)
                            .id(idx)
                            .onAppear {
                                if idx == displayedElements.count/2 {
                                    getNextPage()
                                }
                            }
                    }
                }

                if let search {
                    if !displayedElements.isEmpty {
                        SearchSectionFooter()
                    }
                    SearchResults(query: search.query)
                }
            }
            .padding(20)
        }
        .onChange(of: search?.query) { getNextPage() }
    }

    init(source: InfiniteSource<Element>, @ViewBuilder item: @escaping ([Element], Int) -> Item) {
        self.source = source
        self.item = item
    }

}

//
//  InfiniteList.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI
import AppKit
import SoundCloud

/// Where the elements of an infinitely scrolling view come from.
enum InfiniteSource<Element: Decodable&Identifiable&Filterable&Hashable> {
    /// Loads the first page, the following ones are loaded through its `next` URL.
    case page(() async throws -> Page<Element>)
    /// Loads all ids at once, then the elements in batches of ids.
    case array(() async throws -> [String], ([String]) async throws -> [Element])
}

struct InfiniteList<Element: Decodable&Identifiable&Filterable&Hashable, Row: View>: View {
    
    private var source: InfiniteSource<Element>
    private var row: (Element) -> Row
    
    @Environment(\.header) private var header: AnyView
    @Environment(\.search) private var search: Search?
    
    var body: some View {
        switch source {
        case .page(let firstPage):
            PageView(firstPage: firstPage, content: list)
        case .array(let loadIDs, let loadElements):
            ArrayView(loadIDs: loadIDs, loadElements: loadElements, content: list)
        }
    }
    
    @ViewBuilder func list(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
        let displayedElements = search.map { search in elements.filter { $0.contains(search.query) } } ?? elements
        
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let search {
                    // The section of the main view is left out if nothing in it matches
                    if !displayedElements.isEmpty {
                        SearchSectionHeader(title: search.scope)
                    }
                }
                else {
                    header
                }
                
                ForEach(0..<displayedElements.count, id: \.self) { idx in
                    Spacer()
                        .frame(height: 16)
                    
                    row(displayedElements[idx])
                        .id(idx)
                        .onAppear {
                            // Repeated calls are ignored while a page is loading
                            if idx >= displayedElements.count/2 {
                                getNextPage()
                            }
                        }
                    
                    Spacer()
                        .frame(height: 8)
                    Divider()
                }
                
                if let search {
                    NextPageTrigger(elementCount: elements.count, getNextPage: getNextPage)

                    if !displayedElements.isEmpty {
                        // Every row already ends with a divider
                        SearchSectionFooter(showsDivider: false)
                    }
                    SearchResults(query: search.query)
                }
            }
            .padding(.horizontal)
        }
        .playbackContext(displayedElements)
        .onChange(of: search?.query) { getNextPage() }
    }
    
    init(source: InfiniteSource<Element>, @ViewBuilder row: @escaping (Element) -> Row) {
        self.source = source
        self.row = row
    }

}

/// Requests the next page whenever it is visible. While searching, the rows only show the
/// matching elements, so a loaded page without matches wouldn't make any row appear to request more.
struct NextPageTrigger: View {

    /// The number of loaded elements, including the ones not matching the search.
    var elementCount: Int
    var getNextPage: () -> ()

    var body: some View {
        Color.clear
            .frame(height: 1)
            // A new identity for every loaded page makes `onAppear` fire again if it's still visible
            .id(elementCount)
            .onAppear(perform: getNextPage)
    }

}

extension View {
    
    func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        self.environment(\.header, AnyView(content()))
    }
    
}

struct HeaderKey: EnvironmentKey {
    
    static let defaultValue = AnyView(EmptyView())
    
}

extension EnvironmentValues {
    
    var header: AnyView {
        get { self[HeaderKey.self] }
        set { self[HeaderKey.self] = newValue }
    }
    
}

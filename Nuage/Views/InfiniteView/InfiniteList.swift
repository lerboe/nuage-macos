//
//  InfiniteList.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI
import Introspect
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
    
    @State private var filter = ""
    @State private var isSearching = false
    
    @Environment(\.header) private var header: AnyView
    @Environment(MenuCommands.self) private var commands
    
    var body: some View {
        switch source {
        case .page(let firstPage):
            PageView(firstPage: firstPage, content: list)
        case .array(let loadIDs, let loadElements):
            ArrayView(loadIDs: loadIDs, loadElements: loadElements, content: list)
        }
    }
    
    @ViewBuilder func list(for elements: [Element], getNextPage: @escaping () -> ()) -> some View {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<displayedElements.count+1, id: \.self) {idx in
                        if idx == 0 {
                            header
                        }
                        else {
                            Spacer()
                                .frame(height: 16)
                            
                            row(displayedElements[idx-1])
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
                    }
                }
                .padding(.horizontal)
            }
            .playbackContext(displayedElements)
            .onChange(of: commands.filterRequests) { withAnimation { isSearching = true } }
            .onExitCommand(perform: stopFiltering)
        }
    }
    
    private func stopFiltering() {
        withAnimation {
            isSearching = false
            filter = ""
        }
    }
    
    init(source: InfiniteSource<Element>, @ViewBuilder row: @escaping (Element) -> Row) {
        self.source = source
        self.row = row
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

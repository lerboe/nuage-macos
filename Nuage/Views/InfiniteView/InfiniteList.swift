//
//  InfiniteList.swift
//  Nuage
//
//  Created by Laurin Brandner on 15.12.20.
//

import SwiftUI
import Combine
import Introspect
import AppKit
import SoundCloud

enum InfinitePublisher<Element: Decodable&Identifiable&Filterable&Hashable> {
    case page(AnyPublisher<Page<Element>, Error>)
    case array(AnyPublisher<[String], Error>, ([String]) -> AnyPublisher<[Element], Error>)
}

struct InfiniteList<Element: Decodable&Identifiable&Filterable&Hashable, Row: View>: View {
    
    private var publisher: InfinitePublisher<Element>
    private var row: (Element) -> Row
    
    @State private var filter = ""
    @State private var isSearching = false
    
    @Environment(\.header) private var header: AnyView
    @EnvironmentObject private var commands: CommandSubject
    
    var body: some View {
        if case let .page(publisher) = publisher {
            PageView(publisher: publisher, content: list)
        }
        else if case let .array(arrayPublisher, pagePublisher) = publisher {
            ArrayView(arrayPublisher: arrayPublisher, pagePublisher: pagePublisher, content: list)
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
            .onReceive(commands.filter) { withAnimation { isSearching = true } }
            .onExitCommand(perform: stopFiltering)
        }
    }
    
    private func stopFiltering() {
        withAnimation {
            isSearching = false
            filter = ""
        }
    }
    
    init(publisher: InfinitePublisher<Element>, @ViewBuilder row: @escaping (Element) -> Row) {
        self.publisher = publisher
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

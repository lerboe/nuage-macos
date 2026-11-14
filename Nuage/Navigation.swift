//
//  Navigation.swift
//  Nuage
//
//  Created by Laurin Brandner on 28.07.23.
//

import SwiftUI
import SoundCloud

private let userPlaylistSeparator = "@@USERPLAYLIST@@"
private let systemPlaylistSeparator = "@@SYSTEMPLAYLIST@@"

enum SidebarItem: RawRepresentable {
    case discover
    case stream
    case likes
    case history
    case following
    case userPlaylist(String, String)
    case systemPlaylist(String, String)

    init?(rawValue: String) {
        switch rawValue {
        case "discover": self = .discover
        case "stream": self = .stream
        case "likes": self = .likes
        case "history": self = .history
        case "following": self = .following
        default:
            if rawValue.contains(userPlaylistSeparator) {
                let components = rawValue.split(separator: userPlaylistSeparator)
                guard components.count == 2 else { return nil }
                
                self = .userPlaylist(String(components[0]), String(components[1]))
            }
            else {
                let components = rawValue.split(separator: systemPlaylistSeparator)
                guard components.count == 2 else { return nil }
                
                self = .systemPlaylist(String(components[0]), String(components[1]))
            }            
        }
    }
    
    var rawValue: String {
        switch self {
        case .discover: return "discover"
        case .stream: return "stream"
        case .likes: return "likes"
        case .history: return "history"
        case .following: return "following"
        case .userPlaylist(let name, let id): return name+userPlaylistSeparator+id
        case .systemPlaylist(let name, let id): return name+systemPlaylistSeparator+id
        }
    }
    
    var title: String {
        switch self {
        case .userPlaylist(let name, _): return name
        case .systemPlaylist(let name, _): return name
        default: return rawValue.capitalized
        }
    }
    
    var imageName: String? {
        switch self {
        case .discover: return "sparkles"
        case .stream: return "bolt.horizontal.fill"
        case .likes: return "heart.fill"
        case .history: return "clock.fill"
        case .following: return "person.2.fill"
        default: return nil
        }
    }
    
}

extension SidebarItem: Hashable {
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(title.hashValue)
        if case .userPlaylist(_, let id) = self {
            hasher.combine(id.hashValue)
        }
        else if case .systemPlaylist(_, let urn) = self {
            hasher.combine(urn.hashValue)
        }
    }
    
}

extension SidebarItem: Identifiable {
    
    var id: String {
        if case .userPlaylist(_, let id) = self {
            return id
        }
        if case .systemPlaylist(_, let urn) = self {
            return urn
        }
        return title
    }
    
}

enum Station: Hashable {
    case track(Track)
    case artist(User)
}

extension EnvironmentValues {
    
    /// The navigation value of the content that is currently shown, e.g. the user of a profile.
    @Entry var presentedValue: AnyHashable?
    
}

extension View {
    
    /// Marks `value` as the content shown by this view, so that links within it don't navigate to it again.
    func presenting<V: Hashable>(_ value: V) -> some View {
        environment(\.presentedValue, AnyHashable(value))
    }
    
}

/// A `NavigationLink` that is only added if it doesn't link to the content that is currently shown,
/// otherwise just its label is shown. This avoids pushing the same content over and over again.
struct DestinationLink<Value: Hashable, Label: View>: View {
    
    private var value: Value
    private var label: Label
    
    @Environment(\.presentedValue) private var presentedValue: AnyHashable?
    
    var body: some View {
        if presentedValue == AnyHashable(value) {
            label
        }
        else {
            NavigationLink(value: value) { label }
        }
    }
    
    init(value: Value, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }
    
}

extension DestinationLink where Label == Text {
    
    init(_ title: String, value: Value) {
        self.init(value: value) { Text(title) }
    }
    
}

//
//  UserGrid.swift
//  Nuage
//
//  Created by Laurin Brandner on 27.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import SoundCloud

struct UserGrid<Element: Decodable&Identifiable&Filterable&Hashable>: View {
    
    var source: InfiniteSource<Element>
    private var transform: (Element) -> User
    
    var body: some View {
        InfiniteGrid(source: source) { users, idx in
            let user = transform(users[idx])
            NavigationLink(value: user) {
                UserItem(user: user)
            }
            .buttonStyle(.plain)
        }
    }
    
}

extension UserGrid where Element == User {
    
    init(for firstPage: @escaping () async throws -> Page<User>) {
        self.init(source: .page(firstPage)) { $0 }
    }
    
}

extension UserGrid where Element == Recommendation {
    
    init(for firstPage: @escaping () async throws -> Page<Recommendation>) {
        self.init(source: .page(firstPage)) { $0.user }
    }
    
}

struct UserItem: View {
    
    var user: User
    
    var body: some View {
        VStack(alignment: .center) {
            RemoteImage(url: user.avatarURL, cornerRadius: 50)
                .frame(width: 100, height: 100)
            
            Text(user.username)
                .bold()
                .lineLimit(1)
            
            HStack(spacing: 2) {
                Text(format(count: user.followerCount ?? 0))
                Image(systemName: "person.2.fill")
                
                Spacer()
                    .frame(width: 8)
                
                Text(format(count: user.trackCount ?? 0))
                Image(systemName: "waveform")
            }
            .foregroundColor(.secondary)
        }
    }

}

//struct UserList_Previews: PreviewProvider {
//    static var previews: some View {
//        UserList()
//    }
//}

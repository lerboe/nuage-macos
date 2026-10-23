//
//  LoginView.swift
//  Nuage
//
//  Created by Laurin Brandner on 04.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI

struct LoginView: View {
    
    private var onLogin: (String, Date?) -> ()
    
    var body: some View {
        WebView(url: URL(string: "https://soundcloud.com/signin")!)
            .cookie(name: "oauth_token") { cookie in
                onLogin(cookie.value, cookie.expiresDate)
            }
            .frame(minWidth: 1000, minHeight: 700)
            .navigationTitle("Login")
    }
    
    init(onLogin: @escaping (String, Date?) -> ()) {
        self.onLogin = onLogin
    }
    
}

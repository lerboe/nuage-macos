//
//  WebView.swift
//  Nuage
//
//  Created by Laurin Brandner on 24.01.21.
//

import SwiftUI
import AppKit
import WebKit
import Combine

typealias CookieHandler = ((HTTPCookie) -> ())

struct WebView: NSViewRepresentable {
    
    private var url: URL
    private var handlers = [(String, CookieHandler)]()
    
    init(url: URL) {
        self.url = url
    }
    
    func makeCoordinator() -> WebViewCoordinator {
        return WebViewCoordinator()
    }
    
    func makeNSView(context: Self.Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        let view = WKWebView(frame: .zero, configuration: conf)
        view.load(URLRequest(url: url))
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        
        context.coordinator.handlers = handlers
        context.coordinator.webView = view
        
        return view
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.handlers = handlers
    }
    
    func cookie(name: String, handler: @escaping CookieHandler) -> WebView {
        var view = self
        view.handlers.append((name, handler))
        return view
    }
    
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, ObservableObject {

    var handlers = [(String, CookieHandler)]()
    var webView: WKWebView? {
        didSet {
            webView?.publisher(for: \.url)
                .sink { [weak self] _ in self?.scanCookiesForAccessToken() }
                .store(in: &cancellables)
        }
    }
    private var cancellables = Set<AnyCancellable>()

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        scanCookiesForAccessToken()
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        
        let size = NSSize(width: windowFeatures.width?.doubleValue ?? 500, height: windowFeatures.height?.doubleValue ?? 500)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.closable, .titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.center()
        
        return view
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
    }
    
    private func scanCookiesForAccessToken() {
        guard let webView = webView else { return }
        let store = webView.configuration.websiteDataStore
        
        let handlers = self.handlers
        store.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                for (name, handler) in handlers {
                    if name == cookie.name {
                        handler(cookie)
                    }
                }
            }
        }
    }
    
}

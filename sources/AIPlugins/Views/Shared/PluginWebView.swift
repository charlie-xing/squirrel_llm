import SwiftUI
import WebKit

/// A SwiftUI wrapper for WKWebView with integrated WebViewBridge
/// This replaces the old JSCore + WebView approach with a pure WKWebView solution
struct PluginWebView: NSViewRepresentable {
    let viewModel: PluginViewModel
    let tabId: UUID
    let htmlContent: String
    let settings: AppSettings?
    let isActive: Bool  // Only active tab sets WebView reference

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Register message handlers for JS -> Swift communication
        userContentController.add(context.coordinator.bridge, name: "callAI")
        userContentController.add(context.coordinator.bridge, name: "log")
        userContentController.add(context.coordinator.bridge, name: "getSettings")
        userContentController.add(context.coordinator.bridge, name: "runPythonScript")
        userContentController.add(context.coordinator.bridge, name: "consoleLog")

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background

        // Set navigation delegate to track loading completion
        webView.navigationDelegate = context.coordinator

        // Enable Safari Web Inspector for debugging
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        } else {
            // For older versions, enable developer extras
            UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtras")
        }

        // Link bridge to webView
        context.coordinator.bridge.webView = webView
        context.coordinator.webView = webView
        context.coordinator.viewModel = viewModel

        // Store WebView reference in coordinator
        context.coordinator.isActive = isActive

        // Only set viewModel.webView if this is the active tab
        if isActive {
            print("PluginWebView: Setting WebView reference for active tab \(tabId.uuidString.prefix(8))")
            viewModel.webView = webView
        }

        // Load initial content
        if !htmlContent.isEmpty {
            webView.loadHTMLString(htmlContent, baseURL: nil)
            context.coordinator.lastLoadedHTML = htmlContent
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Update active state and WebView reference
        let wasActive = context.coordinator.isActive
        context.coordinator.isActive = isActive

        // If this tab became active, update the viewModel reference
        if isActive && !wasActive {
            print("PluginWebView: Tab \(tabId.uuidString.prefix(8)) became active, updating WebView reference")
            viewModel.webView = nsView
        }

        // Only reload if content has changed
        if htmlContent != context.coordinator.lastLoadedHTML && !htmlContent.isEmpty {
            print("PluginWebView: Loading new HTML content (length: \(htmlContent.count))")
            nsView.loadHTMLString(htmlContent, baseURL: nil)
            context.coordinator.lastLoadedHTML = htmlContent
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tabId: tabId, settings: settings, initialHTML: htmlContent)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate {
        let bridge: WebViewBridge
        var lastLoadedHTML: String
        var isActive: Bool = false
        weak var webView: WKWebView?
        weak var viewModel: PluginViewModel?

        init(tabId: UUID, settings: AppSettings?, initialHTML: String) {
            self.bridge = WebViewBridge(tabId: tabId, settings: settings)
            self.lastLoadedHTML = initialHTML
            super.init()
        }

        // WKNavigationDelegate method - called when page finishes loading
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("PluginWebView: WebView finished loading")
        }

        // WKNavigationDelegate method - called if loading fails
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("PluginWebView: WebView failed to load: \(error.localizedDescription)")
        }
    }
}

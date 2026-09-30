import SwiftUI
import WebKit

@main
struct IMCDailyApp: App {
    var body: some Scene {
        WindowGroup {
            PracticeView()
                .ignoresSafeArea()
        }
    }
}

/// Shows the IMC Daily page. It loads the live version from GitHub Pages so new
/// topics arrive without reinstalling, and falls back to a copy bundled in the app
/// when there is no internet.
struct PracticeView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "copy")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.scrollView.backgroundColor = .systemBackground
        // The page handles the notch and home bar itself with env(safe-area-inset-*).
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulledToRefresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        context.coordinator.web = web
        context.coordinator.loadLive()
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let site = URL(string: "https://lewiscodeswebsites.github.io/imc-revision/")!

    weak var web: WKWebView?
    private var showingOfflineCopy = false

    func loadLive() {
        showingOfflineCopy = false
        let request = URLRequest(url: Self.site, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 12)
        web?.load(request)
    }

    @objc func pulledToRefresh(_ sender: UIRefreshControl) {
        loadLive()
    }

    private func loadOfflineCopy(_ webView: WKWebView) {
        guard !showingOfflineCopy,
              let url = Bundle.main.url(forResource: "offline", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else { return }
        showingOfflineCopy = true
        // Same base URL as the live site, so the streak and stats are shared.
        webView.loadHTMLString(html, baseURL: Self.site)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    private func handle(_ error: Error, in webView: WKWebView) {
        webView.scrollView.refreshControl?.endRefreshing()
        if (error as NSError).code == NSURLErrorCancelled { return }
        loadOfflineCopy(webView)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Open links to other websites in Safari instead of inside the app.
        if action.navigationType == .linkActivated,
           let url = action.request.url,
           url.host != Self.site.host {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "copy", let text = message.body as? String {
            UIPasteboard.general.string = text
        }
    }
}

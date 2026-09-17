import SwiftUI
import WebKit

struct FeedbackWebView: View {
    @StateObject private var state: FeedbackWebState

    init(url: URL, refreshDestination: @escaping @MainActor () async -> URL?) {
        _state = StateObject(wrappedValue: FeedbackWebState(url: url, refreshDestination: refreshDestination))
    }

    var body: some View {
        ZStack {
            WebViewSurface(webView: state.webView)
                .ignoresSafeArea()

            if state.isLoading && !state.hasContent {
                Color.white.ignoresSafeArea()
                ProgressView().controlSize(.large)
                    .accessibilityLabel("网页加载中")
                    .accessibilityIdentifier("webViewSpinner")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if state.isLoading {
                ProgressView(value: max(0.05, state.progress))
                    .tint(VeloTheme.accent)
                    .accessibilityLabel("网页加载进度")
                    .accessibilityIdentifier("webViewProgress")
                    .animation(.easeOut(duration: 0.2), value: state.progress)
            }
        }
        .tint(VeloTheme.accent)
        .task { state.start() }
        .onDisappear { state.stop() }
    }
}

@MainActor
final class FeedbackWebState: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published private(set) var progress = 0.0
    @Published private(set) var isLoading = true
    @Published private(set) var hasContent = false
    private let initialURL: URL
    private let refreshDestination: @MainActor () async -> URL?
    private(set) var recoveryTask: Task<Void, Never>?
    private var isActive = true
    private var started = false
    private var progressObservation: NSKeyValueObservation?
    private let refreshControl = UIRefreshControl()

    init(url: URL, webView: WKWebView = WKWebView(), refreshDestination: @escaping @MainActor () async -> URL?) {
        self.webView = webView
        initialURL = url
        self.refreshDestination = refreshDestination
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.alwaysBounceVertical = true
        refreshControl.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoading else { return }
                self.progress = self.webView.estimatedProgress
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        load(initialURL)
    }

    private func load(_ url: URL) {
        isLoading = true
        progress = 0
        webView.load(URLRequest(url: url, timeoutInterval: 30))
    }

    @objc private func refreshPage() {
        guard isActive, !isLoading, recoveryTask == nil else {
            refreshControl.endRefreshing()
            return
        }
        isLoading = true
        progress = 0
        if webView.url != nil {
            webView.reload()
        } else {
            load(initialURL)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              WebDestinationURL.parse(url.absoluteString) != nil || url.absoluteString == "about:blank" else {
            isLoading = false
            refreshControl.endRefreshing()
            if navigationAction.targetFrame?.isMainFrame != false { recover() }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            webView.load(navigationAction.request)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        progress = 0
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasContent = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasContent = true
        progress = 1
        isLoading = false
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        hasContent = false
        recover()
    }

    private func handleFailure(_ error: Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else {
            if !webView.isLoading {
                isLoading = false
                refreshControl.endRefreshing()
            }
            return
        }
        recover()
    }

    private func recover() {
        refreshControl.endRefreshing()
        guard isActive, recoveryTask == nil else { return }
        isLoading = false
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.recoveryTask = nil }
            guard let url = await self.refreshDestination(),
                  !Task.isCancelled, self.isActive else { return }
            self.load(url)
        }
    }

    func stop() {
        isActive = false
        refreshControl.endRefreshing()
        recoveryTask?.cancel()
        recoveryTask = nil
        webView.stopLoading()
    }
}

private struct WebViewSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }
}

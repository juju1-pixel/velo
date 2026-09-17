import SwiftUI
import WebKit

struct FeedbackWebView: View {
    @StateObject private var state: FeedbackWebState
    private let inset: Bool

    init(
        url: URL,
        refreshDestination: @escaping @MainActor () async -> URL? = { nil },
        onURLChange: @escaping (URL) -> Void = { _ in },
        recover: Bool = true,
        inset: Bool = false
    ) {
        self.inset = inset
        _state = StateObject(wrappedValue: FeedbackWebState(
            url: url,
            refreshDestination: refreshDestination,
            onURLChange: onURLChange,
            recover: recover
        ))
    }

    var body: some View {
        ZStack {
            WebViewSurface(webView: state.webView)
                .ignoresSafeArea(edges: inset ? [] : .all)

            if state.isLoading && !state.hasContent {
                Color.white.ignoresSafeArea(edges: inset ? [] : .all)
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
    private let onURLChange: (URL) -> Void
    private let allowsRecovery: Bool
    private let refreshDestination: @MainActor () async -> URL?
    private(set) var recoveryTask: Task<Void, Never>?
    private var isActive = true
    private var started = false
    private var rejectedHTTP = false
    private var progressObservation: NSKeyValueObservation?
    private let refreshControl = UIRefreshControl()

    init(
        url: URL,
        webView: WKWebView = WKWebView(),
        refreshDestination: @escaping @MainActor () async -> URL?,
        onURLChange: @escaping (URL) -> Void = { _ in },
        recover: Bool = true
    ) {
        self.webView = webView
        initialURL = url
        self.refreshDestination = refreshDestination
        self.onURLChange = onURLChange
        allowsRecovery = recover
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

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           (400...599).contains(response.statusCode) {
            rejectedHTTP = true
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
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
        if let url = webView.url, WebDestinationURL.parse(url.absoluteString) != nil {
            onURLChange(url)
        }
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
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            if rejectedHTTP {
                rejectedHTTP = false
                recover()
                return
            }
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
        guard allowsRecovery, isActive, recoveryTask == nil else {
            isLoading = false
            refreshControl.endRefreshing()
            return
        }
        isLoading = false
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.recoveryTask = nil }
            guard let url = await self.refreshDestination(),
                  !Task.isCancelled, self.isActive else { return }
            self.onURLChange(url)
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
        webView.scrollView.refreshControl?.endRefreshing()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }
}

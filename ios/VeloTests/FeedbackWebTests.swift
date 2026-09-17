import XCTest
import WebKit
@testable import Velo

final class FeedbackWebTests: XCTestCase {
    private func configuration(path: String = "/destination", base: String = "https://fixture.invalid/") -> FeedbackAPIConfiguration {
        FeedbackAPIConfiguration(baseURL: base, path: path, appID: "velo-test", appKey: "local-test-key",
                                 source: "ios", version: "1.0.0", requestDomain: "")
    }

    func testSignatureMatchesClearCalcProtocolAndOmitsEmptyFields() {
        let fields = ["appId": "velo-test", "requestId": "ABC", "source": "ios", "udid": "XYZ",
                      "version": "1.0.0", "deviceInfo": "", "reqDomain": ""]
        XCTAssertEqual(FeedbackAPIClient.signature(for: fields, appKey: "local-test-key"),
                       "f3c550ea34857c62adc32c65d1b22446")
    }

    func testPOSTHasExpectedFieldsAndFreshIdentifiers() throws {
        let client = FeedbackAPIClient(configuration: configuration())
        let first = try client.makeRequest()
        let second = try client.makeRequest()
        let fields = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(first.httpBody))
        let other = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(second.httpBody))
        XCTAssertEqual(first.url?.absoluteString, "https://fixture.invalid/destination")
        XCTAssertEqual(first.httpMethod, "POST")
        XCTAssertEqual(first.timeoutInterval, 15)
        XCTAssertEqual(first.value(forHTTPHeaderField: "Content-Type"), "application/json;charset=UTF-8")
        XCTAssertEqual(Set(fields.keys), Set(["appId", "deviceInfo", "udid", "source", "reqDomain", "requestId", "version", "sign"]))
        for key in ["udid", "requestId"] {
            let value = try XCTUnwrap(fields[key])
            XCTAssertEqual(value.count, 32)
            XCTAssertTrue(value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
            XCTAssertNotEqual(value, other[key])
        }
        XCTAssertEqual(fields["deviceInfo"], "")
        XCTAssertEqual(fields["sign"], FeedbackAPIClient.signature(for: fields, appKey: "local-test-key"))
        XCTAssertFalse(fields.values.contains("local-test-key"))
    }

    func testUnconfiguredAndNonHTTPSEndpointsAreRejectedBeforeSending() {
        let empty = FeedbackAPIConfiguration(baseURL: "", path: "", appID: "", appKey: "", source: "", version: "1.0.0", requestDomain: "")
        XCTAssertThrowsError(try FeedbackAPIClient(configuration: empty).makeRequest())
        XCTAssertThrowsError(try FeedbackAPIClient(configuration: configuration(base: "http://fixture.invalid")).makeRequest())
    }

    func testOnlyBooleanTrueWithValidHTTPSDestinationIsAccepted() throws {
        let valid = Data(#"{"result":true,"url":" https://example.test/page?q=1 "}"#.utf8)
        XCTAssertEqual(try FeedbackAPIClient.destination(from: valid)?.absoluteString, "https://example.test/page?q=1")
        for value in [#"{"result":false,"url":"https://example.test"}"#,
                      #"{"result":true}"#,
                      #"{"result":true,"url":"http://example.test"}"#,
                      #"{"result":true,"url":"javascript:alert(1)"}"#,
                      #"{"result":true,"url":"https:/page"}"#] {
            XCTAssertNil(try FeedbackAPIClient.destination(from: Data(value.utf8)))
        }
        for value in [#"{"result":1,"url":"https://example.test"}"#,
                      #"{"result":"true","url":"https://example.test"}"#,
                      "invalid JSON"] {
            XCTAssertThrowsError(try FeedbackAPIClient.destination(from: Data(value.utf8)))
        }
    }

    func testURLValidationRejectsCredentialsAndRelativePaths() {
        for value in ["https://user:password@example.test", "/page", "file:///tmp/page", "https://"] {
            XCTAssertNil(WebDestinationURL.parse(value))
        }
    }

    func testClientAcceptsSuccessAndRejectsHTTPFailure() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [FeedbackFixtureProtocol.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        let client = FeedbackAPIClient(configuration: configuration(), session: session)
        let destination = try await client.fetchDestination()
        XCTAssertEqual(destination?.absoluteString, "https://example.test/page")
        do {
            _ = try await FeedbackAPIClient(configuration: configuration(path: "/failure"), session: session).fetchDestination()
            XCTFail("HTTP failures must not open a webpage")
        } catch FeedbackAPIClient.RequestError.httpResponse {
            // Expected.
        }
    }

    @MainActor
    func testOrdinaryFeedbackNeverCallsTheAPI() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let client = FixedDestinationClient(url: URL(string: "https://example.test/page"))
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        await router.handleFeedback("希望增加行程记录")
        let count = await client.requestCount
        XCTAssertEqual(count, 0)
        XCTAssertNil(router.destinationURL)
    }

    @MainActor
    func testSuccessfulTriggerPersistsAndRestoresWithoutAnotherRequest() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let url = URL(string: "https://example.test/page")!
        let client = FixedDestinationClient(url: url)
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        await router.handleFeedback(" 9889\n")
        XCTAssertEqual(router.destinationURL, url)
        XCTAssertFalse(router.isRequesting)
        XCTAssertTrue(defaults.value.bool(forKey: WebDestinationRouter.enabledKey))
        let restored = WebDestinationRouter(defaults: defaults.value, client: client)
        XCTAssertEqual(restored.destinationURL, url)
        let count = await client.requestCount
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testDeniedAndFailedRequestsLeaveNativeRouteAndPersistenceUntouched() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        for fails in [false, true] {
            let client = FixedDestinationClient(url: nil, fails: fails)
            let router = WebDestinationRouter(defaults: defaults.value, client: client)
            await router.handleFeedback("9889")
            XCTAssertNil(router.destinationURL)
            XCTAssertFalse(router.isRequesting)
            XCTAssertFalse(defaults.value.bool(forKey: WebDestinationRouter.enabledKey))
            XCTAssertNil(defaults.value.string(forKey: WebDestinationRouter.urlKey))
        }
    }

    @MainActor
    func testInvalidSavedURLCannotRestoreWebRoute() {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        defaults.value.set(true, forKey: WebDestinationRouter.enabledKey)
        defaults.value.set("http://example.test/page", forKey: WebDestinationRouter.urlKey)
        XCTAssertNil(WebDestinationRouter(defaults: defaults.value).destinationURL)
    }

    @MainActor
    func testConcurrentTriggersOnlySendOneRequest() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let client = DeferredDestinationClient()
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        let first = Task { await router.handleFeedback("9889") }
        await client.waitForRequest()
        await router.handleFeedback("9889")
        let count = await client.requestCount
        XCTAssertEqual(count, 1)
        await client.finish()
        await first.value
        XCTAssertNotNil(router.destinationURL)
    }

    @MainActor
    func testCancelledRequestCannotPersistLateSuccess() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let client = DeferredDestinationClient()
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        let request = Task { await router.handleFeedback("9889") }
        await client.waitForRequest()
        request.cancel()
        await client.finish()
        await request.value
        XCTAssertNil(router.destinationURL)
        XCTAssertFalse(router.isRequesting)
        XCTAssertFalse(defaults.value.bool(forKey: WebDestinationRouter.enabledKey))
    }

    @MainActor
    func testRefreshReplacesSavedDestinationAndRestoresNewURL() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        defaults.value.set(true, forKey: WebDestinationRouter.enabledKey)
        defaults.value.set("https://example.test/old", forKey: WebDestinationRouter.urlKey)
        let newURL = URL(string: "https://example.test/new")!
        let client = FixedDestinationClient(url: newURL)
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        let result = await router.refreshDestination()
        XCTAssertEqual(result, newURL)
        XCTAssertEqual(router.destinationURL, newURL)
        XCTAssertEqual(WebDestinationRouter(defaults: defaults.value).destinationURL, newURL)
        let count = await client.requestCount
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testDeniedOrFailedRefreshKeepsExistingURL() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let oldURL = "https://example.test/old"
        defaults.value.set(true, forKey: WebDestinationRouter.enabledKey)
        defaults.value.set(oldURL, forKey: WebDestinationRouter.urlKey)
        for fails in [false, true] {
            let router = WebDestinationRouter(defaults: defaults.value,
                                              client: FixedDestinationClient(url: nil, fails: fails))
            let result = await router.refreshDestination()
            XCTAssertNil(result)
            XCTAssertEqual(router.destinationURL?.absoluteString, oldURL)
            XCTAssertEqual(defaults.value.string(forKey: WebDestinationRouter.urlKey), oldURL)
            XCTAssertTrue(defaults.value.bool(forKey: WebDestinationRouter.enabledKey))
            XCTAssertFalse(router.isRequesting)
        }
    }

    @MainActor
    func testConcurrentAndCancelledRefreshCannotReplaceExistingURL() async {
        let defaults = temporaryDefaults()
        defer { clear(defaults) }
        let oldURL = "https://example.test/old"
        defaults.value.set(true, forKey: WebDestinationRouter.enabledKey)
        defaults.value.set(oldURL, forKey: WebDestinationRouter.urlKey)
        let client = DeferredDestinationClient()
        let router = WebDestinationRouter(defaults: defaults.value, client: client)
        let request = Task { await router.refreshDestination() }
        await client.waitForRequest()
        let duplicate = await router.refreshDestination()
        XCTAssertNil(duplicate)
        let count = await client.requestCount
        XCTAssertEqual(count, 1)
        request.cancel()
        await client.finish()
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertEqual(router.destinationURL?.absoluteString, oldURL)
        XCTAssertEqual(defaults.value.string(forKey: WebDestinationRouter.urlKey), oldURL)
    }

    @MainActor
    func testWebFailureLoadsFreshAPIURLInsteadOfRetryingOldURL() async {
        let webView = RecordingWebView()
        let fresh = URL(string: "https://example.test/new")!
        let state = FeedbackWebState(url: URL(string: "https://example.test/old")!, webView: webView) { fresh }
        state.start()
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cannotFindHost))
        await state.recoveryTask?.value
        XCTAssertEqual(webView.loadedURLs.map(\.absoluteString), ["https://example.test/old", fresh.absoluteString])
        XCTAssertTrue(state.isLoading)
        state.stop()
    }

    @MainActor
    func testWebFailureWithDeniedAPIKeepsContentWithoutLoadingAgain() async {
        let webView = RecordingWebView()
        var requests = 0
        let state = FeedbackWebState(url: URL(string: "https://example.test/old")!, webView: webView) {
            requests += 1
            return nil
        }
        state.start()
        state.webView(webView, didFinish: nil)
        state.webView(webView, didFail: nil, withError: URLError(.networkConnectionLost))
        await state.recoveryTask?.value
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(webView.loadedURLs.count, 1)
        XCTAssertTrue(state.hasContent)
        XCTAssertFalse(state.isLoading)
        state.stop()
    }

    @MainActor
    func testDuplicateWebFailuresAndDisappearanceCancelLateNavigation() async {
        let client = DeferredDestinationClient()
        let webView = RecordingWebView()
        let state = FeedbackWebState(url: URL(string: "https://example.test/old")!, webView: webView) {
            try? await client.fetchDestination()
        }
        state.start()
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.timedOut))
        await client.waitForRequest()
        state.webViewWebContentProcessDidTerminate(webView)
        let request = state.recoveryTask
        state.stop()
        await client.finish()
        await request?.value
        let count = await client.requestCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(webView.loadedURLs.count, 1)
    }

    @MainActor
    func testCancelledWebNavigationDoesNotRequestAnotherURL() async {
        let webView = RecordingWebView()
        var requests = 0
        let state = FeedbackWebState(url: URL(string: "https://example.test/old")!, webView: webView) {
            requests += 1
            return nil
        }
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        XCTAssertNil(state.recoveryTask)
        XCTAssertEqual(requests, 0)
        state.stop()
    }

    @MainActor
    func testPullRefreshReloadsCurrentPageAndEndsOnCompletion() throws {
        let webView = RecordingWebView()
        var requests = 0
        let state = FeedbackWebState(url: URL(string: "https://example.test/initial")!, webView: webView) {
            requests += 1
            return nil
        }
        state.start()
        webView.currentURL = URL(string: "https://example.test/current")!
        state.webView(webView, didFinish: nil)
        let control = try XCTUnwrap(webView.scrollView.refreshControl)
        XCTAssertTrue(webView.scrollView.alwaysBounceVertical)
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        XCTAssertEqual(webView.reloadedURLs, [webView.currentURL])
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(state.isLoading)
        state.webView(webView, didFinish: nil)
        XCTAssertFalse(control.isRefreshing)
        XCTAssertFalse(state.isLoading)
        state.stop()
    }

    @MainActor
    func testPullRefreshFailureEndsSpinnerAndRequestsNewDestination() async throws {
        let webView = RecordingWebView()
        var requests = 0
        let state = FeedbackWebState(url: webView.currentURL, webView: webView) {
            requests += 1
            return nil
        }
        state.webView(webView, didFinish: nil)
        let control = try XCTUnwrap(webView.scrollView.refreshControl)
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.timedOut))
        await state.recoveryTask?.value
        XCTAssertFalse(control.isRefreshing)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(webView.reloadedURLs.count, 1)
        XCTAssertTrue(webView.loadedURLs.isEmpty)
        state.stop()
    }

    @MainActor
    func testAboutPageFailureDoesNotRecoverOrChangeURL() async {
        let webView = RecordingWebView()
        var requests = 0
        var changed: [URL] = []
        let state = FeedbackWebState(
            url: URL(string: "https://juju1-pixel.github.io/velo/doc/about.html")!,
            webView: webView,
            refreshDestination: {
                requests += 1
                return URL(string: "https://example.test/replaced")
            },
            onURLChange: { changed.append($0) },
            recover: false
        )
        state.start()
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cannotFindHost))
        await state.recoveryTask?.value
        state.webViewWebContentProcessDidTerminate(webView)
        await state.recoveryTask?.value
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(changed.isEmpty)
        XCTAssertNil(state.recoveryTask)
        XCTAssertEqual(webView.loadedURLs.map(\.absoluteString), ["https://juju1-pixel.github.io/velo/doc/about.html"])
        XCTAssertFalse(state.isLoading)
        state.stop()
    }

    func testAboutPageURLIsPublicHTTPS() {
        XCTAssertEqual(AppInformation.aboutPageURL.scheme, "https")
        XCTAssertEqual(AppInformation.aboutPageURL.absoluteString, "https://juju1-pixel.github.io/velo/doc/about.html")
        XCTAssertNotNil(WebDestinationURL.parse(AppInformation.aboutPageURL.absoluteString))
    }

    @MainActor
    func testPullRefreshIgnoresBusyOrStoppedPageAndEndsOnCancellation() throws {
        let webView = RecordingWebView()
        let state = FeedbackWebState(url: webView.currentURL, webView: webView) { nil }
        let control = try XCTUnwrap(webView.scrollView.refreshControl)
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        XCTAssertTrue(webView.reloadedURLs.isEmpty)
        XCTAssertFalse(control.isRefreshing)
        state.webView(webView, didFinish: nil)
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        state.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        XCTAssertFalse(control.isRefreshing)
        XCTAssertNil(state.recoveryTask)
        state.stop()
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        XCTAssertEqual(webView.reloadedURLs.count, 1)
        XCTAssertFalse(control.isRefreshing)
    }

    private func temporaryDefaults() -> (name: String, value: UserDefaults) {
        let name = "VeloFeedbackWebTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    private func clear(_ defaults: (name: String, value: UserDefaults)) {
        defaults.value.removePersistentDomain(forName: defaults.name)
    }
}

private final class FeedbackFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url?.path == "/failure" ? 503 : 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"result":true,"url":"https://example.test/page"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor FixedDestinationClient: FeedbackDestinationFetching {
    private let url: URL?
    private let fails: Bool
    private(set) var requestCount = 0
    init(url: URL?, fails: Bool = false) { self.url = url; self.fails = fails }
    func fetchDestination() async throws -> URL? {
        requestCount += 1
        if fails { throw URLError(.notConnectedToInternet) }
        return url
    }
}

private actor DeferredDestinationClient: FeedbackDestinationFetching {
    private(set) var requestCount = 0
    private var response: CheckedContinuation<URL?, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func fetchDestination() async throws -> URL? {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            response = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitForRequest() async {
        guard response == nil else { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() {
        response?.resume(returning: URL(string: "https://example.test/page"))
        response = nil
    }
}

@MainActor
private final class RecordingWebView: WKWebView {
    private(set) var loadedURLs: [URL] = []
    var currentURL = URL(string: "https://example.test/current")!
    override var url: URL? { currentURL }
    private(set) var reloadedURLs: [URL] = []
    override func reload() -> WKNavigation? {
        reloadedURLs.append(currentURL)
        return nil
    }
    override func load(_ request: URLRequest) -> WKNavigation? {
        if let url = request.url { loadedURLs.append(url) }
        return nil
    }
}

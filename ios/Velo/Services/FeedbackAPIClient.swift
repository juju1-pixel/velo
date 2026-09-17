import CryptoKit
import Foundation

struct FeedbackAPIConfiguration: Sendable {
    // Fill in the real service configuration here. No test endpoint is shipped.
    static let current = FeedbackAPIConfiguration(
        baseURL: "", path: "", appID: "", appKey: "", source: "",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        requestDomain: ""
    )

    let baseURL: String
    let path: String
    let appID: String
    let appKey: String
    let source: String
    let version: String
    let requestDomain: String
}

enum WebDestinationURL {
    static func parse(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

protocol FeedbackDestinationFetching: Sendable {
    func fetchDestination() async throws -> URL?
}

struct FeedbackAPIClient: FeedbackDestinationFetching {
    let configuration: FeedbackAPIConfiguration
    private let session: URLSession

    init(configuration: FeedbackAPIConfiguration = .current, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchDestination() async throws -> URL? {
        let (data, response) = try await session.data(for: makeRequest())
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else { throw RequestError.httpResponse }
        return try Self.destination(from: data)
    }

    func makeRequest() throws -> URLRequest {
        let base = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = configuration.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !path.isEmpty,
              !configuration.appID.isEmpty, !configuration.appKey.isEmpty else {
            throw RequestError.notConfigured
        }
        let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = WebDestinationURL.parse(endpoint) else { throw RequestError.invalidURL }

        // Match ClearCalc's field names. Both IDs are fresh random strings, not device identifiers.
        var fields = [
            "appId": configuration.appID,
            "deviceInfo": "",
            "udid": Self.randomIdentifier(),
            "source": configuration.source,
            "reqDomain": configuration.requestDomain,
            "requestId": Self.randomIdentifier(),
            "version": configuration.version,
        ]
        fields["sign"] = Self.signature(for: fields, appKey: configuration.appKey)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(fields)
        return request
    }

    static func destination(from data: Data) throws -> URL? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result, let rawURL = response.url else { return nil }
        return WebDestinationURL.parse(rawURL)
    }

    static func signature(for fields: [String: String], appKey: String) -> String {
        let joined = fields.keys.sorted().compactMap { key -> String? in
            guard key != "sign", let value = fields[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "&")
        guard !joined.isEmpty else { return "" }
        // MD5 is required by the existing ClearCalc server protocol.
        return Insecure.MD5.hash(data: Data((joined + "&appKey=" + appKey).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func randomIdentifier() -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        return String((0..<32).map { _ in alphabet.randomElement()! })
    }

    private struct Response: Decodable {
        let result: Bool
        let url: String?
    }

    enum RequestError: Error {
        case notConfigured, invalidURL, httpResponse
    }
}

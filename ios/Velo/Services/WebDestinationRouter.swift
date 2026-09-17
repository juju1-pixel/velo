import Combine
import Foundation

@MainActor
final class WebDestinationRouter: ObservableObject {
    static let triggerText = "9889"
    static let enabledKey = "hasUnlockedInternalWebView"
    static let urlKey = "internalWebViewURL"

    @Published private(set) var destinationURL: URL?
    @Published private(set) var isRequesting = false
    private let defaults: UserDefaults
    private let client: any FeedbackDestinationFetching

    init(defaults: UserDefaults = .standard, client: any FeedbackDestinationFetching = FeedbackAPIClient()) {
        self.defaults = defaults
        self.client = client
        if defaults.bool(forKey: Self.enabledKey), let value = defaults.string(forKey: Self.urlKey) {
            destinationURL = WebDestinationURL.parse(value)
        }
    }

    func handleFeedback(_ text: String) async {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) == Self.triggerText,
              !isRequesting, destinationURL == nil, !Task.isCancelled else { return }
        _ = await requestDestination()
    }

    func refreshDestination() async -> URL? {
        guard destinationURL != nil else { return nil }
        return await requestDestination()
    }

    private func requestDestination() async -> URL? {
        guard !isRequesting, !Task.isCancelled else { return nil }
        isRequesting = true
        defer { isRequesting = false }
        do {
            guard let destination = try await client.fetchDestination(),
                  let validated = WebDestinationURL.parse(destination.absoluteString),
                  !Task.isCancelled else { return nil }
            defaults.set(validated.absoluteString, forKey: Self.urlKey)
            defaults.set(true, forKey: Self.enabledKey)
            destinationURL = validated
            return validated
        } catch {
            // A denied or failed request leaves the current route and saved URL unchanged.
        }
        return nil
    }
}

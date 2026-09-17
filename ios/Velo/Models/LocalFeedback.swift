import Foundation

struct LocalFeedback: Codable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
}

struct LocalFeedbackStore {
    static let maximumLength = 100
    static let maximumCount = 5
    let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "Velo/messages.json")) {
        self.fileURL = fileURL
    }

    func load() throws -> [LocalFeedback] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([LocalFeedback].self, from: Data(contentsOf: fileURL))
    }

    @discardableResult
    func save(_ text: String) throws -> LocalFeedback {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumLength else {
            throw FeedbackError.invalidText
        }
        var messages = try load()
        let message = LocalFeedback(id: UUID(), text: trimmed, createdAt: Date())
        messages.append(message)
        messages = Array(messages.suffix(Self.maximumCount))
        let data = try JSONEncoder().encode(messages)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return message
    }

    private enum FeedbackError: Error {
        case invalidText
    }
}

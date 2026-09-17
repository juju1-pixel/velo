import XCTest
@testable import Velo

final class LocalFeedbackTests: XCTestCase {
    private var directory: URL!
    private var store: LocalFeedbackStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = LocalFeedbackStore(fileURL: directory.appendingPathComponent("messages.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSubmittedMessagesSurviveReloadAndAppendInOrder() throws {
        try store.save("  希望增加行程记录 🚲\n")
        try store.save("第二条留言")
        let reloaded = try LocalFeedbackStore(fileURL: store.fileURL).load()
        XCTAssertEqual(reloaded.map(\.text), ["希望增加行程记录 🚲", "第二条留言"])
        XCTAssertNotEqual(reloaded[0].id, reloaded[1].id)
    }

    func testBlankAndOversizedMessagesDoNotCreateStorage() {
        XCTAssertThrowsError(try store.save(" \n\t"))
        XCTAssertThrowsError(try store.save(String(repeating: "字", count: 101)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testUnreadableExistingMessagesAreNotOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("invalid json".utf8)
        try original.write(to: store.fileURL)
        XCTAssertThrowsError(try store.save("新的留言"))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testOnlyLatestFiveMessagesRemainOnDisk() throws {
        for index in 1...7 {
            try store.save("留言 \(index)")
        }
        let persisted = try JSONDecoder().decode([LocalFeedback].self, from: Data(contentsOf: store.fileURL))
        XCTAssertEqual(persisted.map(\.text), (3...7).map { "留言 \($0)" })
    }

    func testExactlyOneHundredCharactersAreAccepted() throws {
        let text = String(repeating: "🚲", count: 100)
        try store.save(text)
        XCTAssertEqual(try store.load().first?.text, text)
    }

    func testWriteFailureIsReported() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blockingFile)
        let failingStore = LocalFeedbackStore(fileURL: blockingFile.appendingPathComponent("messages.json"))
        XCTAssertThrowsError(try failingStore.save("保留原文"))
    }
}

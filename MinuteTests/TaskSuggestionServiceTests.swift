import XCTest
import SwiftData
@testable import Minute

@MainActor
final class TaskSuggestionServiceTests: XCTestCase {
    func testImportIsIdempotentAndDoesNotResurrectDismissedSuggestion() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let context = container.mainContext
        let service = TaskSuggestionService(modelContext: context)
        let input = TaskSuggestionInput(
            fingerprint: "gmail:thread-1:reply",
            title: "Reply with the revised draft",
            sourceType: "gmail",
            sourceLabel: "Gmail",
            sourceURL: "https://mail.google.com/example",
            evidenceSnippet: "A revision was requested.",
            reason: "The latest reply asks for changes.",
            project: nil,
            dueDate: nil,
            confidence: 0.9,
            rank: 0
        )

        let first = try service.importSuggestions([input], sourceRequestID: "run-1")
        XCTAssertEqual(first.count, 1)
        try service.dismiss(first[0])

        let second = try service.importSuggestions([input], sourceRequestID: "run-2")
        XCTAssertTrue(second.isEmpty)
        let stored = try context.fetch(FetchDescriptor<TaskSuggestion>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].status, TaskSuggestionStatus.dismissed)
    }

    func testAcceptCreatesOneTaskAndBecomesTerminal() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let context = container.mainContext
        let service = TaskSuggestionService(modelContext: context)
        let input = TaskSuggestionInput(
            fingerprint: "drive:file-1:review",
            title: "Review the application draft",
            sourceType: "drive",
            sourceLabel: "Drive",
            sourceURL: nil,
            evidenceSnippet: nil,
            reason: nil,
            project: nil,
            dueDate: nil,
            confidence: 0.8,
            rank: 0
        )
        let suggestion = try XCTUnwrap(
            service.importSuggestions([input], sourceRequestID: "run-1").first
        )

        let firstTask = try service.accept(suggestion)
        let secondTask = try service.accept(suggestion)

        XCTAssertEqual(firstTask.id, secondTask.id)
        XCTAssertEqual(suggestion.status, TaskSuggestionStatus.accepted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }
}

import XCTest
import SwiftData
@testable import Minute

@MainActor
final class MinuteStoreMigrationTests: XCTestCase {
    func testExplicitStoreOverrideUsesAbsolutePath() {
        let expected = URL(fileURLWithPath: "/tmp/minute-explicit-store/default.store")

        let resolved = MinuteStoreLocation.resolvedURL(
            environment: ["MINUTE_STORE_URL": expected.path]
        )

        XCTAssertEqual(resolved.standardizedFileURL, expected.standardizedFileURL)
    }

    func testCurrentStoreFixtureMigratesWithoutLosingCoreEntities() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["MINUTE_MIGRATION_FIXTURE"], !fixturePath.isEmpty else {
            throw XCTSkip("Set MINUTE_MIGRATION_FIXTURE to a consistent pre-change SQLite store snapshot.")
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MinuteMigrationTests-(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let migratedStore = temporaryDirectory.appendingPathComponent("default.store")
        try fileManager.copyItem(at: URL(fileURLWithPath: fixturePath), to: migratedStore)

        let counts: (areas: Int, projects: Int, tasks: Int, checklistItems: Int, suggestions: Int, taskDefaultsAreEmpty: Bool) = try {
            let container = try MinuteModelContainerFactory.makeContainer(
                configuration: .local(url: migratedStore)
            )
            let context = container.mainContext
            let migratedTasks = try context.fetch(FetchDescriptor<TaskItem>())
            return (
                try context.fetchCount(FetchDescriptor<Area>()),
                try context.fetchCount(FetchDescriptor<Project>()),
                migratedTasks.count,
                try context.fetchCount(FetchDescriptor<TaskChecklistItem>()),
                try context.fetchCount(FetchDescriptor<TaskSuggestion>()),
                migratedTasks.allSatisfy { $0.notes == nil && $0.workStartedAt == nil && $0.checklist.isEmpty }
            )
        }()

        XCTAssertEqual(counts.areas, expectedCount(named: "MINUTE_MIGRATION_EXPECTED_AREAS", environment: environment))
        XCTAssertEqual(counts.projects, expectedCount(named: "MINUTE_MIGRATION_EXPECTED_PROJECTS", environment: environment))
        XCTAssertEqual(counts.tasks, expectedCount(named: "MINUTE_MIGRATION_EXPECTED_TASKS", environment: environment))
        XCTAssertEqual(counts.checklistItems, 0)
        XCTAssertEqual(counts.suggestions, 0)
        XCTAssertTrue(counts.taskDefaultsAreEmpty)
    }

    private func expectedCount(named key: String, environment: [String: String]) -> Int {
        guard let value = environment[key], let count = Int(value) else {
            XCTFail("Set \(key) when running the migration fixture test.")
            return -1
        }
        return count
    }
}

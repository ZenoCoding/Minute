import XCTest
@testable import Minute

@MainActor
final class MinuteWidgetSnapshotTests: XCTestCase {
    func testSnapshotBuilderFiltersCompletedTasksAndSortsActionableTasks() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let laterDate = now.addingTimeInterval(3_600)

        let laterTask = TaskItem(title: "Later", orderIndex: 1, dueDate: laterDate)
        let soonerTask = TaskItem(title: "Sooner", orderIndex: 0, dueDate: now)
        let completedTask = TaskItem(title: "Done", orderIndex: -1, dueDate: now)
        completedTask.isCompleted = true

        let snapshot = MinuteWidgetSnapshotBuilder.makeSnapshot(
            from: [laterTask, completedTask, soonerTask],
            now: now
        )

        XCTAssertEqual(snapshot.tasks.map(\.title), ["Sooner", "Later"])
        XCTAssertFalse(snapshot.tasks.contains { $0.title == "Done" })
        XCTAssertFalse(snapshot.tasks[0].isOverdue)
    }

    func testSnapshotStoreRoundTripsThroughInjectedDefaults() {
        let defaults = UserDefaults(suiteName: "MinuteWidgetSnapshotTests")!
        defaults.removePersistentDomain(forName: "MinuteWidgetSnapshotTests")
        defer { defaults.removePersistentDomain(forName: "MinuteWidgetSnapshotTests") }

        let snapshot = MinuteWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600),
            tasks: [MinuteWidgetTask(id: UUID(), title: "Keep moving")]
        )
        let store = MinuteWidgetSnapshotStore(defaults: defaults)

        store.write(snapshot)

        XCTAssertEqual(store.read(), snapshot)
    }
}

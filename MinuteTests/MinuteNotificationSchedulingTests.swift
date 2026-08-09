import XCTest
import SwiftData
@testable import Minute

@MainActor
final class MinuteNotificationSchedulingTests: XCTestCase {
    func testRequestUsesStableTaskIdentifierAndDueDate() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let project = try service.createProject(name: "Essays")
        let now = Date(timeIntervalSince1970: 1_000)
        let dueDate = now.addingTimeInterval(3_600)
        let task = try service.createTask(title: "Submit draft", project: project, dueDate: dueDate)

        let request = try XCTUnwrap(
            MinuteTaskNotificationRequestDeriver.request(for: task, now: now)
        )

        XCTAssertEqual(
            request.identifier,
            "com.tychoyoung.Minute.task.\(task.id.uuidString.lowercased())"
        )
        XCTAssertEqual(request.taskID, task.id)
        XCTAssertEqual(request.title, "Submit draft")
        XCTAssertEqual(request.body, "Essays")
        XCTAssertEqual(request.fireDate, dueDate)
    }

    func testCompletedPastAndUndatedTasksDoNotProduceRequests() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let now = Date(timeIntervalSince1970: 1_000)

        let undated = try service.createTask(title: "Undated", project: nil)
        let past = try service.createTask(
            title: "Past",
            project: nil,
            dueDate: now.addingTimeInterval(-1)
        )
        let completed = try service.createTask(
            title: "Completed",
            project: nil,
            dueDate: now.addingTimeInterval(1_000)
        )
        completed.isCompleted = true

        XCTAssertNil(MinuteTaskNotificationRequestDeriver.request(for: undated, now: now))
        XCTAssertNil(MinuteTaskNotificationRequestDeriver.request(for: past, now: now))
        XCTAssertNil(MinuteTaskNotificationRequestDeriver.request(for: completed, now: now))
    }

    func testCoordinatorCancelsStaleRequestsWhenTaskIsCompletedOrDeleted() async throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let now = Date(timeIntervalSince1970: 1_000)
        let task = try service.createTask(
            title: "Due task",
            project: nil,
            dueDate: now.addingTimeInterval(1_000)
        )
        try service.save()

        let scheduler = RecordingNotificationScheduler()
        let coordinator = MinuteNotificationCoordinator(
            modelContext: container.mainContext,
            scheduler: scheduler,
            notificationCenter: NotificationCenter()
        )

        try await coordinator.reconcile(now: now)
        XCTAssertEqual(scheduler.cancelAllCallCount, 1)
        XCTAssertEqual(scheduler.scheduled.map(\.taskID), [task.id])

        task.isCompleted = true
        try service.save()
        try await coordinator.reconcile(now: now)

        XCTAssertEqual(scheduler.cancelAllCallCount, 2)
        XCTAssertTrue(scheduler.scheduled.isEmpty)

        let deletedTask = try service.createTask(
            title: "Deleted task",
            project: nil,
            dueDate: now.addingTimeInterval(2_000)
        )
        try service.save()
        try await coordinator.reconcile(now: now)
        XCTAssertEqual(scheduler.scheduled.map(\.taskID), [deletedTask.id])

        service.deleteTask(deletedTask)
        try service.save()
        try await coordinator.reconcile(now: now)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    @MainActor
    private final class RecordingNotificationScheduler: MinuteNotificationScheduler {
        private(set) var scheduled: [MinuteTaskNotificationRequest] = []
        private(set) var cancelAllCallCount = 0

        func schedule(_ request: MinuteTaskNotificationRequest) async throws {
            scheduled.append(request)
        }

        func cancel(taskID: UUID) {
            scheduled.removeAll { $0.taskID == taskID }
        }

        func cancelAllMinuteTaskNotifications() async {
            cancelAllCallCount += 1
            scheduled.removeAll()
        }
    }
}

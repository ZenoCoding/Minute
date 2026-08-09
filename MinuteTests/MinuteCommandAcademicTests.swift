import XCTest
import SwiftData
@testable import Minute

@MainActor
final class MinuteCommandAcademicTests: XCTestCase {
    func testChecklistCompletionInvariantsAndExclusiveWorkFocus() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let project = try service.createProject(name: "Academic")
        let task = try service.createTask(
            title: "Finish paper",
            project: project,
            checklist: [
                TaskChecklistDraft(title: "Read source"),
                TaskChecklistDraft(title: "Write section")
            ]
        )
        let otherTask = try service.createTask(title: "Review notes", project: project)
        let firstWorkDate = Date(timeIntervalSince1970: 100)
        let secondWorkDate = Date(timeIntervalSince1970: 200)

        try service.startWork(task, at: firstWorkDate)
        XCTAssertEqual(task.workStartedAt, firstWorkDate)
        try service.startWork(otherTask, at: secondWorkDate)
        XCTAssertNil(task.workStartedAt)
        XCTAssertEqual(otherTask.workStartedAt, secondWorkDate)

        let firstItem = try XCTUnwrap(task.checklist.first)
        let secondItem = try XCTUnwrap(task.checklist.last)
        let completionDate = Date(timeIntervalSince1970: 300)
        service.setChecklistItemCompletion(firstItem, isCompleted: true, at: completionDate)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)

        service.setChecklistItemCompletion(secondItem, isCompleted: true, at: completionDate)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, completionDate)
        XCTAssertTrue(task.checklist.allSatisfy(\.isCompleted))
        XCTAssertNil(task.workStartedAt)

        service.setChecklistItemCompletion(firstItem, isCompleted: false, at: completionDate)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
        XCTAssertTrue(secondItem.isCompleted)

        service.setTaskCompletion(task, isCompleted: true, at: completionDate)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(task.checklist.allSatisfy(\.isCompleted))
        service.setTaskCompletion(task, isCompleted: false, at: completionDate)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
        XCTAssertTrue(task.checklist.allSatisfy(\.isCompleted))
    }

    func testDuplicateCopiesAcademicFieldsAndChecklistStateButResetsTaskState() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let project = try service.createProject(name: "Academic")
        let dueDate = Date(timeIntervalSince1970: 1_000)
        let source = try service.createTask(
            title: "Prepare defense",
            project: project,
            estimatedDuration: 3_600,
            dueDate: dueDate,
            recurrenceInterval: "weekly",
            notes: "Bring the printed figures.",
            checklist: [
                TaskChecklistDraft(title: "Check figures", isCompleted: true),
                TaskChecklistDraft(title: "Practice opening")
            ]
        )
        try service.startWork(source, at: Date(timeIntervalSince1970: 1_100))

        let duplicate = try service.duplicateTask(source)

        XCTAssertNotEqual(source.id, duplicate.id)
        XCTAssertIdentical(source.project, duplicate.project)
        XCTAssertEqual(duplicate.title, source.title)
        XCTAssertEqual(duplicate.notes, source.notes)
        XCTAssertEqual(duplicate.dueDate, dueDate)
        XCTAssertEqual(duplicate.estimatedDuration, 3_600)
        XCTAssertEqual(duplicate.recurrenceInterval, "weekly")
        XCTAssertEqual(duplicate.isRecurring, true)
        XCTAssertFalse(duplicate.isCompleted)
        XCTAssertNil(duplicate.completedAt)
        XCTAssertNil(duplicate.workStartedAt)
        XCTAssertEqual(duplicate.checklist.map(\.title), source.checklist.map(\.title))
        XCTAssertEqual(duplicate.checklist.map(\.isCompleted), source.checklist.map(\.isCompleted))
        XCTAssertEqual(duplicate.checklist.map(\.orderIndex), [0, 1])
        XCTAssertEqual(Set(duplicate.checklist.map(\.id)).count, duplicate.checklist.count)
        XCTAssertTrue(Set(duplicate.checklist.map(\.id)).isDisjoint(with: Set(source.checklist.map(\.id))))
    }

    func testAcademicRequestAndTaskSnapshotCodableCoverage() throws {
        let requestJSON = Data(
            #"{"version":1,"requestID":"request-1","action":"update","entity":"task","payload":{"identifier":"TASK","notes":"Study notes","checklist":[{"title":"Read","isCompleted":true},{"title":"Outline","isCompleted":false}]}}"#.utf8
        )
        let request = try JSONDecoder().decode(MinuteCommandRequest.self, from: requestJSON)
        XCTAssertEqual(request.payload?.notes, "Study notes")
        XCTAssertEqual(request.payload?.checklist?.map(\.title), ["Read", "Outline"])
        XCTAssertEqual(request.payload?.checklist?.map(\.isCompleted), [true, false])

        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)
        let task = try service.createTask(
            title: "Study",
            project: nil,
            notes: "Review chapter 4",
            checklist: [TaskChecklistDraft(title: "Read chapter")]
        )
        try service.startWork(task, at: Date(timeIntervalSince1970: 2_000))
        let snapshot = MinuteEntitySnapshot(task: task)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            MinuteEntitySnapshot.self,
            from: encoder.encode(snapshot)
        )
        XCTAssertEqual(decoded.notes, "Review chapter 4")
        XCTAssertEqual(decoded.workStartedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(decoded.checklist?.map(\.title), ["Read chapter"])
        XCTAssertEqual(decoded.checklist?.map(\.orderIndex), [0])
    }
}

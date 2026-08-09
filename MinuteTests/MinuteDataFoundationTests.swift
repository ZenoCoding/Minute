import XCTest
import SwiftData
@testable import Minute

@MainActor
final class MinuteDataFoundationTests: XCTestCase {
    func testInMemoryContainerUsesTheSharedSchema() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        XCTAssertEqual(
            Set(container.schema.entities.map(\.name)),
            Set(["Area", "Project", "TaskItem", "TaskChecklistItem", "TaskSuggestion"])
        )
    }

    func testCloudKitRelationshipsAreOptionalAndHaveExplicitInverses() throws {
        let area = try XCTUnwrap(
            MinuteModelContainerFactory.schema.entities.first { $0.name == "Area" }
        )
        let project = try XCTUnwrap(
            MinuteModelContainerFactory.schema.entities.first { $0.name == "Project" }
        )
        let task = try XCTUnwrap(
            MinuteModelContainerFactory.schema.entities.first { $0.name == "TaskItem" }
        )
        let checklistItem = try XCTUnwrap(
            MinuteModelContainerFactory.schema.entities.first { $0.name == "TaskChecklistItem" }
        )

        let areaProjects = area.properties.first { $0.name == "projectsStorage" } as? Schema.Relationship
        let projectArea = project.properties.first { $0.name == "area" } as? Schema.Relationship
        let projectTasks = project.properties.first { $0.name == "tasksStorage" } as? Schema.Relationship
        let taskProject = task.properties.first { $0.name == "project" } as? Schema.Relationship
        let taskChecklist = task.properties.first { $0.name == "checklistStorage" } as? Schema.Relationship
        let checklistTask = checklistItem.properties.first { $0.name == "task" } as? Schema.Relationship

        XCTAssertEqual(areaProjects?.inverseName, "area")
        XCTAssertEqual(projectArea?.inverseName, "projectsStorage")
        XCTAssertEqual(projectTasks?.inverseName, "project")
        XCTAssertEqual(taskProject?.inverseName, "tasksStorage")
        XCTAssertEqual(taskChecklist?.inverseName, "task")
        XCTAssertEqual(checklistTask?.inverseName, "checklistStorage")
        XCTAssertEqual(areaProjects?.minimumModelCount, 0)
        XCTAssertEqual(projectTasks?.minimumModelCount, 0)
        XCTAssertEqual(taskChecklist?.minimumModelCount, 0)
        XCTAssertNil(checklistTask?.minimumModelCount)
    }

    func testServiceCRUDWorksWithOptionalRelationshipStorage() throws {
        let container = try MinuteModelContainerFactory.makeContainer(configuration: .inMemory)
        let service = MinuteDataService(modelContext: container.mainContext)

        let area = try service.createArea(name: " School ")
        let project = try service.createProject(name: " Essays ", areaName: "School")
        let task = try service.createTask(
            title: " Draft introduction ",
            project: project,
            notes: " Add citations ",
            checklist: [
                TaskChecklistDraft(title: "Find sources"),
                TaskChecklistDraft(title: "Write paragraph", isCompleted: true)
            ]
        )
        try service.save()

        XCTAssertEqual(area.projects.map(\.name), ["Essays"])
        XCTAssertEqual(project.tasks.map(\.title), ["Draft introduction"])
        XCTAssertIdentical(task.project, project)
        XCTAssertEqual(task.notes, "Add citations")
        XCTAssertEqual(task.checklist.map(\.title), ["Find sources", "Write paragraph"])
        XCTAssertEqual(task.checklist.map(\.isCompleted), [false, true])
        XCTAssertFalse(task.isCompleted)
    }

    func testAcademicModelDefaultsAreOptionalAndChecklistFacadeStartsEmpty() {
        let task = TaskItem(title: "Read")
        let item = TaskChecklistItem(title: "Open the book")

        XCTAssertNil(task.notes)
        XCTAssertNil(task.workStartedAt)
        XCTAssertEqual(task.checklist.count, 0)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
        XCTAssertNil(item.task)
        XCTAssertEqual(item.orderIndex, 0)
    }
}

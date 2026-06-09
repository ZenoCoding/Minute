import Foundation
import SwiftData

enum MinuteDataError: LocalizedError {
    case invalidName(String)
    case invalidTitle
    case areaNotFound(String)
    case projectNotFound(String)
    case duplicateArea(String)
    case duplicateProject(String)
    case invalidProjectStatus(String)
    case entityNotFound(String, String)
    case ambiguousIdentifier(String, String)
    case entityHasChildren(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let entity):
            return "\(entity) name cannot be empty."
        case .invalidTitle:
            return "Task title cannot be empty."
        case .areaNotFound(let name):
            return "Area '\(name)' was not found."
        case .projectNotFound(let name):
            return "Project '\(name)' was not found."
        case .duplicateArea(let name):
            return "Area '\(name)' already exists."
        case .duplicateProject(let name):
            return "Project '\(name)' already exists."
        case .invalidProjectStatus(let status):
            return "Unknown project status '\(status)'."
        case .entityNotFound(let entity, let identifier):
            return "\(entity) '\(identifier)' was not found."
        case .ambiguousIdentifier(let entity, let identifier):
            return "\(entity) identifier '\(identifier)' is ambiguous. Use its UUID instead."
        case .entityHasChildren(let entity, let identifier):
            return "\(entity) '\(identifier)' contains child data. Retry with recursive deletion enabled."
        }
    }
}

@MainActor
struct MinuteDataService {
    let modelContext: ModelContext

    func createArea(
        name: String,
        themeColor: String = "007AFF",
        iconName: String = "folder",
        orderIndex: Int? = nil,
        sourceRequestID: String? = nil
    ) throws -> Area {
        if let existing = try area(forSourceRequestID: sourceRequestID) {
            return existing
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw MinuteDataError.invalidName("Area")
        }
        guard try findArea(named: cleanName) == nil else {
            throw MinuteDataError.duplicateArea(cleanName)
        }

        let resolvedOrderIndex: Int
        if let orderIndex {
            resolvedOrderIndex = orderIndex
        } else {
            resolvedOrderIndex = try fetchAreas().count
        }

        let area = Area(
            name: cleanName,
            themeColor: normalizedHexColor(themeColor),
            iconName: iconName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "folder",
            orderIndex: resolvedOrderIndex
        )
        area.sourceRequestID = sourceRequestID
        modelContext.insert(area)
        return area
    }

    func createProject(
        name: String,
        areaName: String? = nil,
        statusName: String = ProjectStatus.active.rawValue,
        weeklyGoalSeconds: TimeInterval? = nil,
        orderIndex: Int? = nil,
        sourceRequestID: String? = nil
    ) throws -> Project {
        if let existing = try project(forSourceRequestID: sourceRequestID) {
            return existing
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw MinuteDataError.invalidName("Project")
        }
        guard try findProject(named: cleanName) == nil else {
            throw MinuteDataError.duplicateProject(cleanName)
        }
        guard let status = ProjectStatus(rawValue: statusName.lowercased()) else {
            throw MinuteDataError.invalidProjectStatus(statusName)
        }

        let area: Area
        if let areaName = areaName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            guard let existingArea = try findArea(named: areaName) else {
                throw MinuteDataError.areaNotFound(areaName)
            }
            area = existingArea
        } else {
            area = try findOrCreateUnsortedArea()
        }

        let project = Project(
            name: cleanName,
            status: status,
            weeklyGoalSeconds: weeklyGoalSeconds,
            orderIndex: orderIndex ?? area.projects.count,
            area: area
        )
        project.sourceRequestID = sourceRequestID
        modelContext.insert(project)
        return project
    }

    func createTask(
        title: String,
        project: Project?,
        estimatedDuration: TimeInterval? = nil,
        dueDate: Date? = nil,
        recurrenceInterval: String? = nil,
        orderIndex: Int? = nil,
        sourceRequestID: String? = nil
    ) throws -> TaskItem {
        if let existing = try task(forSourceRequestID: sourceRequestID) {
            return existing
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw MinuteDataError.invalidTitle
        }

        let resolvedProject = try project ?? findOrCreateInboxProject()
        let task = TaskItem(
            title: cleanTitle,
            orderIndex: orderIndex ?? resolvedProject.tasks.count,
            project: resolvedProject,
            estimatedDuration: estimatedDuration,
            dueDate: dueDate
        )
        task.sourceRequestID = sourceRequestID
        task.recurrenceInterval = recurrenceInterval
        task.isRecurring = recurrenceInterval != nil
        modelContext.insert(task)
        return task
    }

    func createTask(
        text: String,
        explicitProjectName: String? = nil,
        dueDate: Date? = nil,
        estimatedDuration: TimeInterval? = nil,
        recurrenceInterval: String? = nil,
        orderIndex: Int? = nil,
        parseNaturalLanguage: Bool = true,
        sourceRequestID: String? = nil
    ) throws -> TaskItem {
        if let existing = try task(forSourceRequestID: sourceRequestID) {
            return existing
        }

        let projects = try fetchProjects().filter { $0.status == .active }
        let parsed: SmartInputParser.ComposerResult?
        if parseNaturalLanguage {
            parsed = SmartInputParser.parseForComposer(
                text: text,
                projectCandidates: try projectCandidates(projects: projects)
            )
        } else {
            parsed = nil
        }

        let title = parsed?.cleanTitle.nilIfEmpty ?? text
        let project: Project?
        if let explicitProjectName = explicitProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            guard let explicitProject = try findProject(named: explicitProjectName) else {
                throw MinuteDataError.projectNotFound(explicitProjectName)
            }
            project = explicitProject
        } else if let parsedProjectName = parsed?.projectName {
            project = try findProject(named: parsedProjectName)
        } else {
            project = nil
        }

        return try createTask(
            title: title,
            project: project,
            estimatedDuration: estimatedDuration ?? parsed?.duration,
            dueDate: dueDate ?? parsed?.date,
            recurrenceInterval: recurrenceInterval ?? parsed?.recurrenceInterval,
            orderIndex: orderIndex,
            sourceRequestID: sourceRequestID
        )
    }

    func findArea(named name: String) throws -> Area? {
        let areas = try fetchAreas()
        return areas.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func findProject(named name: String) throws -> Project? {
        let projects = try fetchProjects()
        return projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func resolveArea(_ identifier: String) throws -> Area {
        if let id = UUID(uuidString: identifier),
           let area = try fetchAreas().first(where: { $0.id == id }) {
            return area
        }

        let matches = try fetchAreas().filter {
            $0.name.caseInsensitiveCompare(identifier) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw MinuteDataError.ambiguousIdentifier("Area", identifier)
        }
        guard let area = matches.first else {
            throw MinuteDataError.entityNotFound("Area", identifier)
        }
        return area
    }

    func resolveProject(_ identifier: String) throws -> Project {
        if let id = UUID(uuidString: identifier),
           let project = try fetchProjects().first(where: { $0.id == id }) {
            return project
        }

        let matches = try fetchProjects().filter {
            $0.name.caseInsensitiveCompare(identifier) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw MinuteDataError.ambiguousIdentifier("Project", identifier)
        }
        guard let project = matches.first else {
            throw MinuteDataError.entityNotFound("Project", identifier)
        }
        return project
    }

    func resolveTask(_ identifier: String) throws -> TaskItem {
        if let id = UUID(uuidString: identifier),
           let task = try fetchTasks().first(where: { $0.id == id }) {
            return task
        }

        let matches = try fetchTasks().filter {
            $0.title.caseInsensitiveCompare(identifier) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw MinuteDataError.ambiguousIdentifier("Task", identifier)
        }
        guard let task = matches.first else {
            throw MinuteDataError.entityNotFound("Task", identifier)
        }
        return task
    }

    func updateArea(
        _ area: Area,
        name: String? = nil,
        themeColor: String? = nil,
        iconName: String? = nil,
        orderIndex: Int? = nil
    ) throws {
        if let name {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else {
                throw MinuteDataError.invalidName("Area")
            }
            if let duplicate = try findArea(named: cleanName), duplicate.id != area.id {
                throw MinuteDataError.duplicateArea(cleanName)
            }
            area.name = cleanName
        }
        if let themeColor {
            area.themeColor = normalizedHexColor(themeColor)
        }
        if let iconName {
            area.iconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "folder"
        }
        if let orderIndex {
            area.orderIndex = orderIndex
        }
    }

    func updateProject(
        _ project: Project,
        name: String? = nil,
        areaName: String? = nil,
        statusName: String? = nil,
        weeklyGoalSeconds: TimeInterval? = nil,
        clearWeeklyGoal: Bool = false,
        orderIndex: Int? = nil
    ) throws {
        if let name {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else {
                throw MinuteDataError.invalidName("Project")
            }
            if let duplicate = try findProject(named: cleanName), duplicate.id != project.id {
                throw MinuteDataError.duplicateProject(cleanName)
            }
            project.name = cleanName
        }
        if let areaName {
            project.area = try resolveArea(areaName)
        }
        if let statusName {
            guard let status = ProjectStatus(rawValue: statusName.lowercased()) else {
                throw MinuteDataError.invalidProjectStatus(statusName)
            }
            project.status = status
        }
        if clearWeeklyGoal {
            project.weeklyGoalSeconds = nil
        } else if let weeklyGoalSeconds {
            project.weeklyGoalSeconds = weeklyGoalSeconds
        }
        if let orderIndex {
            project.orderIndex = orderIndex
        }
    }

    func updateTask(
        _ task: TaskItem,
        title: String? = nil,
        projectName: String? = nil,
        dueDate: Date? = nil,
        clearDueDate: Bool = false,
        estimatedDuration: TimeInterval? = nil,
        clearDuration: Bool = false,
        recurrenceInterval: String? = nil,
        clearRecurrence: Bool = false,
        completed: Bool? = nil,
        orderIndex: Int? = nil
    ) throws {
        if let title {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else {
                throw MinuteDataError.invalidTitle
            }
            task.title = cleanTitle
        }
        if let projectName {
            task.project = try resolveProject(projectName)
        }
        if clearDueDate {
            task.dueDate = nil
        } else if let dueDate {
            task.dueDate = dueDate
        }
        if clearDuration {
            task.estimatedDuration = nil
        } else if let estimatedDuration {
            task.estimatedDuration = estimatedDuration
        }
        if clearRecurrence {
            task.recurrenceInterval = nil
            task.isRecurring = false
        } else if let recurrenceInterval {
            task.recurrenceInterval = recurrenceInterval
            task.isRecurring = true
        }
        if let completed {
            task.isCompleted = completed
            task.completedAt = completed ? (task.completedAt ?? Date()) : nil
        }
        if let orderIndex {
            task.orderIndex = orderIndex
        }
    }

    func deleteArea(_ area: Area, recursive: Bool) throws {
        if !recursive && !area.projects.isEmpty {
            throw MinuteDataError.entityHasChildren("Area", area.name)
        }
        modelContext.delete(area)
    }

    func deleteProject(_ project: Project, recursive: Bool) throws {
        if !recursive && !project.tasks.isEmpty {
            throw MinuteDataError.entityHasChildren("Project", project.name)
        }
        modelContext.delete(project)
    }

    func deleteTask(_ task: TaskItem) {
        modelContext.delete(task)
    }

    func findOrCreateUnsortedArea() throws -> Area {
        if let area = try findArea(named: "Unsorted") {
            return area
        }
        return try createArea(
            name: "Unsorted",
            themeColor: "8E8E93",
            iconName: "tray"
        )
    }

    func findOrCreateInboxProject() throws -> Project {
        if let project = try findProject(named: "Inbox") {
            return project
        }
        return try createProject(name: "Inbox", areaName: nil, orderIndex: -1)
    }

    func save() throws {
        try modelContext.save()
    }

    func fetchAreas() throws -> [Area] {
        try modelContext.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func fetchProjects() throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func fetchTasks() throws -> [TaskItem] {
        try modelContext.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func area(forSourceRequestID requestID: String?) throws -> Area? {
        guard let requestID else { return nil }
        return try fetchAreas().first { $0.sourceRequestID == requestID }
    }

    private func project(forSourceRequestID requestID: String?) throws -> Project? {
        guard let requestID else { return nil }
        return try fetchProjects().first { $0.sourceRequestID == requestID }
    }

    private func task(forSourceRequestID requestID: String?) throws -> TaskItem? {
        guard let requestID else { return nil }
        return try fetchTasks().first { $0.sourceRequestID == requestID }
    }

    private func projectCandidates(projects: [Project]) throws -> [SmartInputParser.ProjectCandidate] {
        let tasks = try fetchTasks()
        return projects.map { project in
            let recentTitles = tasks
                .filter { $0.project?.id == project.id }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(12)
                .map(\.title)
            let hints = [project.area?.name].compactMap { $0 } + recentTitles
            return SmartInputParser.ProjectCandidate(name: project.name, hints: hints)
        }
    }

    private func normalizedHexColor(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
            .nilIfEmpty ?? "007AFF"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

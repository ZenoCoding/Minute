import Foundation
import SwiftData

enum MinuteDataError: LocalizedError {
    case invalidName(String)
    case invalidTitle
    case invalidChecklistTitle
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
        case .invalidChecklistTitle:
            return "Checklist item title cannot be empty."
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
        sourceRequestID: String? = nil,
        notes: String? = nil,
        checklist: [TaskChecklistDraft] = []
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
        task.notes = normalizedNotes(notes)
        modelContext.insert(task)
        if !checklist.isEmpty {
            try replaceChecklist(on: task, with: checklist)
        }
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
        sourceRequestID: String? = nil,
        notes: String? = nil,
        checklist: [TaskChecklistDraft] = []
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
            sourceRequestID: sourceRequestID,
            notes: notes,
            checklist: checklist
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
        orderIndex: Int? = nil,
        notes: String? = nil,
        clearNotes: Bool = false,
        checklist: [TaskChecklistDraft]? = nil
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
        if clearNotes {
            task.notes = nil
        } else if let notes {
            task.notes = normalizedNotes(notes)
        }
        if let checklist {
            try replaceChecklist(on: task, with: checklist)
        }
        if let completed {
            setTaskCompletion(task, isCompleted: completed)
        }
        if let orderIndex {
            task.orderIndex = orderIndex
        }
    }

    /// Replaces the task's one-level checklist in the supplied order.
    /// Existing checklist objects are deleted so replacement is deterministic
    /// and idempotent for command/API callers.
    func replaceChecklist(on task: TaskItem, with drafts: [TaskChecklistDraft]) throws {
        let normalizedDrafts = try drafts.map { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw MinuteDataError.invalidChecklistTitle
            }
            return TaskChecklistDraft(title: title, isCompleted: draft.isCompleted)
        }

        for item in task.checklist {
            modelContext.delete(item)
        }

        let replacement = normalizedDrafts.enumerated().map { offset, draft in
            let item = TaskChecklistItem(
                title: draft.title,
                isCompleted: draft.isCompleted,
                orderIndex: offset,
                task: task
            )
            modelContext.insert(item)
            return item
        }
        task.checklist = replacement

        // A replacement is also a checklist state change. An empty list does
        // not alter parent completion, while a non-empty list follows the
        // same invariants as individual item changes.
        if !replacement.isEmpty {
            if replacement.allSatisfy(\.isCompleted) {
                setTaskCompletion(task, isCompleted: true)
            } else if task.isCompleted {
                setTaskCompletion(task, isCompleted: false)
            }
        }
    }

    /// Applies completion state to one checklist item and synchronizes its
    /// parent task without erasing progress when the parent is reopened.
    func setChecklistItemCompletion(
        _ item: TaskChecklistItem,
        isCompleted: Bool,
        at date: Date = Date()
    ) {
        item.isCompleted = isCompleted
        item.completedAt = isCompleted ? (item.completedAt ?? date) : nil

        guard let task = item.task else { return }
        if isCompleted {
            if !task.checklist.isEmpty && task.checklist.allSatisfy(\.isCompleted) {
                setTaskCompletion(task, isCompleted: true, at: date)
            }
        } else if task.isCompleted {
            setTaskCompletion(task, isCompleted: false)
        }
    }

    func setChecklistItemCompletion(
        _ item: TaskChecklistItem,
        completed: Bool,
        at date: Date = Date()
    ) {
        setChecklistItemCompletion(item, isCompleted: completed, at: date)
    }

    /// Applies the parent completion invariant. Completing a task completes
    /// every checklist item and stops active work; reopening preserves item
    /// progress.
    func setTaskCompletion(
        _ task: TaskItem,
        isCompleted: Bool,
        at date: Date = Date()
    ) {
        task.isCompleted = isCompleted
        task.completedAt = isCompleted ? (task.completedAt ?? date) : nil

        if isCompleted {
            for item in task.checklist {
                item.isCompleted = true
                item.completedAt = item.completedAt ?? date
            }
            task.workStartedAt = nil
        }
    }

    func setTaskCompletion(
        _ task: TaskItem,
        completed: Bool,
        at date: Date = Date()
    ) {
        setTaskCompletion(task, isCompleted: completed, at: date)
    }

    /// Starts work on exactly one task at a time.
    func startWork(_ task: TaskItem, at date: Date = Date()) throws {
        for otherTask in try fetchTasks() where otherTask.id != task.id {
            otherTask.workStartedAt = nil
        }
        task.workStartedAt = date
    }

    func startWork(on task: TaskItem, at date: Date = Date()) throws {
        try startWork(task, at: date)
    }

    func stopWork(_ task: TaskItem) {
        task.workStartedAt = nil
    }

    func stopWork(on task: TaskItem) {
        stopWork(task)
    }

    /// Duplicates a task as an incomplete sibling with fresh IDs and no work
    /// state. Checklist titles/order/state are retained.
    func duplicateTask(_ task: TaskItem) throws -> TaskItem {
        let duplicate = TaskItem(
            title: task.title,
            orderIndex: task.orderIndex,
            project: task.project,
            estimatedDuration: task.estimatedDuration,
            dueDate: task.dueDate,
            notes: task.notes
        )
        duplicate.recurrenceInterval = task.recurrenceInterval
        duplicate.isRecurring = task.isRecurring
        duplicate.isCompleted = false
        duplicate.completedAt = nil
        duplicate.workStartedAt = nil
        modelContext.insert(duplicate)

        let drafts = task.checklist.map {
            TaskChecklistDraft(title: $0.title, isCompleted: $0.isCompleted)
        }
        if !drafts.isEmpty {
            try replaceChecklist(on: duplicate, with: drafts)
        }
        // A duplicate remains incomplete even when all copied checklist items
        // were checked on the source task; the copied checklist state is kept.
        duplicate.isCompleted = false
        duplicate.completedAt = nil
        duplicate.workStartedAt = nil
        return duplicate
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

    private func normalizedNotes(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

import Foundation
import SwiftData

struct MinuteCommandRequest: Codable {
    struct Payload: Codable {
        var text: String? = nil
        var name: String? = nil
        var project: String? = nil
        var area: String? = nil
        var dueDate: String? = nil
        var durationSeconds: TimeInterval? = nil
        var recurrence: String? = nil
        var parseNaturalLanguage: Bool? = nil
        var status: String? = nil
        var weeklyGoalSeconds: TimeInterval? = nil
        var themeColor: String? = nil
        var iconName: String? = nil
        var orderIndex: Int? = nil
        var identifier: String? = nil
        var completed: Bool? = nil
        var clearDueDate: Bool? = nil
        var clearDuration: Bool? = nil
        var clearRecurrence: Bool? = nil
        var clearWeeklyGoal: Bool? = nil
        var notes: String? = nil
        var clearNotes: Bool? = nil
        var checklist: [TaskChecklistDraft]? = nil
        var recursive: Bool? = nil
        var limit: Int? = nil
        var suggestions: [TaskSuggestionInput]? = nil
    }

    let version: Int
    let requestID: String
    let action: String
    let entity: String?
    let payload: Payload?
}

struct MinuteCommandReceipt: Codable {
    let version: Int
    let requestID: String
    let status: String
    let entity: String?
    let entityID: String?
    let displayName: String?
    let message: String
    let processedAt: Date
    let items: [MinuteEntitySnapshot]?
}

struct MinuteEntitySnapshot: Codable {
    let entity: String
    let id: String
    let name: String
    let createdAt: Date
    let orderIndex: Int
    let sourceRequestID: String?
    let area: String?
    let project: String?
    let status: String?
    let themeColor: String?
    let iconName: String?
    let weeklyGoalSeconds: TimeInterval?
    let isCompleted: Bool?
    let completedAt: Date?
    let estimatedDuration: TimeInterval?
    let dueDate: Date?
    let isRecurring: Bool?
    let recurrenceInterval: String?
    let notes: String?
    let workStartedAt: Date?
    let checklist: [MinuteChecklistItemSnapshot]?
    let projectCount: Int?
    let taskCount: Int?
    var fingerprint: String? = nil
    var sourceType: String? = nil
    var sourceLabel: String? = nil
    var sourceURL: String? = nil
    var evidenceSnippet: String? = nil
    var reason: String? = nil
    var confidence: Double? = nil

    init(area: Area) {
        entity = "area"
        id = area.id.uuidString
        name = area.name
        createdAt = area.createdAt
        orderIndex = area.orderIndex
        sourceRequestID = area.sourceRequestID
        self.area = nil
        project = nil
        status = nil
        themeColor = area.themeColor
        iconName = area.iconName
        weeklyGoalSeconds = nil
        isCompleted = nil
        completedAt = nil
        estimatedDuration = nil
        dueDate = nil
        isRecurring = nil
        recurrenceInterval = nil
        notes = nil
        workStartedAt = nil
        checklist = nil
        projectCount = area.projects.count
        taskCount = area.projects.reduce(0) { $0 + $1.tasks.count }
    }

    init(project: Project) {
        entity = "project"
        id = project.id.uuidString
        name = project.name
        createdAt = project.createdAt
        orderIndex = project.orderIndex
        sourceRequestID = project.sourceRequestID
        area = project.area?.name
        self.project = nil
        status = project.status.rawValue
        themeColor = nil
        iconName = nil
        weeklyGoalSeconds = project.weeklyGoalSeconds
        isCompleted = nil
        completedAt = nil
        estimatedDuration = nil
        dueDate = nil
        isRecurring = nil
        recurrenceInterval = nil
        notes = nil
        workStartedAt = nil
        checklist = nil
        projectCount = nil
        taskCount = project.tasks.count
    }

    init(task: TaskItem) {
        entity = "task"
        id = task.id.uuidString
        name = task.title
        createdAt = task.createdAt
        orderIndex = task.orderIndex
        sourceRequestID = task.sourceRequestID
        area = task.project?.area?.name
        project = task.project?.name
        status = nil
        themeColor = nil
        iconName = nil
        weeklyGoalSeconds = nil
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        estimatedDuration = task.estimatedDuration
        dueDate = task.dueDate
        isRecurring = task.isRecurring
        recurrenceInterval = task.recurrenceInterval
        notes = task.notes
        workStartedAt = task.workStartedAt
        checklist = task.checklist.map(MinuteChecklistItemSnapshot.init(item:))
        projectCount = nil
        taskCount = nil
    }

    init(suggestion: TaskSuggestion) {
        entity = "suggestion"
        id = suggestion.id.uuidString
        name = suggestion.title
        createdAt = suggestion.generatedAt
        orderIndex = suggestion.rank
        sourceRequestID = suggestion.sourceRequestID
        area = nil
        project = suggestion.inferredProjectName
        status = suggestion.status
        themeColor = nil
        iconName = nil
        weeklyGoalSeconds = nil
        isCompleted = nil
        completedAt = nil
        estimatedDuration = nil
        dueDate = suggestion.dueDate
        isRecurring = nil
        recurrenceInterval = nil
        notes = nil
        workStartedAt = nil
        checklist = nil
        projectCount = nil
        taskCount = nil
        fingerprint = suggestion.fingerprint
        sourceType = suggestion.sourceType
        sourceLabel = suggestion.sourceLabel
        sourceURL = suggestion.sourceURL
        evidenceSnippet = suggestion.evidenceSnippet
        reason = suggestion.reason
        confidence = suggestion.confidence
    }
}

struct MinuteChecklistItemSnapshot: Codable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let orderIndex: Int
    let createdAt: Date

    @MainActor
    init(item: TaskChecklistItem) {
        id = item.id.uuidString
        title = item.title
        isCompleted = item.isCompleted
        completedAt = item.completedAt
        orderIndex = item.orderIndex
        createdAt = item.createdAt
    }
}

enum MinuteCommandAPIError: LocalizedError {
    case unsupportedVersion(Int)
    case unsupportedAction(String)
    case unsupportedEntity(String)
    case missingField(String)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported API version \(version)."
        case .unsupportedAction(let action):
            return "Unsupported action '\(action)'."
        case .unsupportedEntity(let entity):
            return "Unsupported entity '\(entity)'."
        case .missingField(let field):
            return "Missing required field '\(field)'."
        case .invalidDate(let date):
            return "Invalid ISO-8601 date '\(date)'."
        }
    }
}

enum MinuteCommandPaths {
    static func root(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = MinuteStoreLocation
            .resolvedURL(fileManager: fileManager)
            .deletingLastPathComponent()
        return applicationSupport
            .appendingPathComponent("Minute", isDirectory: true)
            .appendingPathComponent("Commands", isDirectory: true)
    }

    static func inbox(fileManager: FileManager = .default) throws -> URL {
        try root(fileManager: fileManager).appendingPathComponent("inbox", isDirectory: true)
    }

    static func receipts(fileManager: FileManager = .default) throws -> URL {
        try root(fileManager: fileManager).appendingPathComponent("receipts", isDirectory: true)
    }
}

@MainActor
final class MinuteCommandProcessor: NSObject {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private var timer: Timer?
    private var isProcessing = false

    init(modelContext: ModelContext, fileManager: FileManager = .default) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        super.init()
    }

    func start() {
        guard timer == nil else { return }

        do {
            try prepareDirectories()
            processPendingRequests()
        } catch {
            print("Minute command API setup failed: \(error)")
        }

        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerDidFire() {
        processPendingRequests()
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: try MinuteCommandPaths.inbox(fileManager: fileManager),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: try MinuteCommandPaths.receipts(fileManager: fileManager),
            withIntermediateDirectories: true
        )
    }

    private func processPendingRequests() {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let inbox = try MinuteCommandPaths.inbox(fileManager: fileManager)
            let requests = try fileManager.contentsOfDirectory(
                at: inbox,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for requestURL in requests {
                process(requestURL)
            }
        } catch {
            print("Minute command API scan failed: \(error)")
        }
    }

    private func process(_ requestURL: URL) {
        let fallbackRequestID = requestURL.deletingPathExtension().lastPathComponent

        do {
            let data = try Data(contentsOf: requestURL)
            let request = try JSONDecoder().decode(MinuteCommandRequest.self, from: data)
            let receiptURL = try receiptURL(requestID: request.requestID)

            if fileManager.fileExists(atPath: receiptURL.path) {
                try? fileManager.removeItem(at: requestURL)
                return
            }

            let receipt = try execute(request)
            try write(receipt: receipt, to: receiptURL)
            try fileManager.removeItem(at: requestURL)
        } catch {
            let receipt = MinuteCommandReceipt(
                version: 1,
                requestID: fallbackRequestID,
                status: "error",
                entity: nil,
                entityID: nil,
                displayName: nil,
                message: error.localizedDescription,
                processedAt: Date(),
                items: nil
            )

            do {
                try write(receipt: receipt, to: receiptURL(requestID: fallbackRequestID))
                try? fileManager.removeItem(at: requestURL)
            } catch {
                print("Minute command API receipt failed: \(error)")
            }
        }
    }

    private func execute(_ request: MinuteCommandRequest) throws -> MinuteCommandReceipt {
        guard request.version == 1 else {
            throw MinuteCommandAPIError.unsupportedVersion(request.version)
        }
        let supportedActions = ["create", "import", "list", "get", "update", "delete", "accept", "dismiss", "ping"]
        guard supportedActions.contains(request.action) else {
            throw MinuteCommandAPIError.unsupportedAction(request.action)
        }

        if request.action == "ping" {
            return MinuteCommandReceipt(
                version: 1,
                requestID: request.requestID,
                status: "success",
                entity: nil,
                entityID: nil,
                displayName: nil,
                message: "Minute command API is ready.",
                processedAt: Date(),
                items: nil
            )
        }

        guard let entity = request.entity else {
            throw MinuteCommandAPIError.missingField("entity")
        }
        let payload = request.payload ?? MinuteCommandRequest.Payload()
        let service = MinuteDataService(modelContext: modelContext)

        if request.action == "import", entity == "suggestion" {
            let suggestions = try TaskSuggestionService(modelContext: modelContext)
                .importSuggestions(payload.suggestions ?? [], sourceRequestID: request.requestID)
            let items = suggestions.map(MinuteEntitySnapshot.init(suggestion:))
            return MinuteCommandReceipt(
                version: 1,
                requestID: request.requestID,
                status: "success",
                entity: entity,
                entityID: nil,
                displayName: nil,
                message: "Imported \(items.count) suggestion\(items.count == 1 ? "" : "s").",
                processedAt: Date(),
                items: items
            )
        }

        if ["accept", "dismiss"].contains(request.action), entity == "suggestion" {
            guard let identifier = payload.identifier else {
                throw MinuteCommandAPIError.missingField("payload.identifier")
            }
            let suggestionService = TaskSuggestionService(modelContext: modelContext)
            let suggestion = try suggestionService.resolve(identifier)
            if request.action == "accept" {
                _ = try suggestionService.accept(suggestion)
            } else {
                try suggestionService.dismiss(suggestion)
            }
            let snapshot = MinuteEntitySnapshot(suggestion: suggestion)
            return MinuteCommandReceipt(
                version: 1,
                requestID: request.requestID,
                status: "success",
                entity: entity,
                entityID: snapshot.id,
                displayName: snapshot.name,
                message: "\(request.action.capitalized)ed suggestion '\(snapshot.name)'.",
                processedAt: Date(),
                items: [snapshot]
            )
        }

        if request.action == "list" {
            return try list(entity: entity, payload: payload, requestID: request.requestID, service: service)
        }

        if request.action == "get" {
            return try get(entity: entity, payload: payload, requestID: request.requestID, service: service)
        }

        if request.action == "update" {
            return try update(entity: entity, payload: payload, requestID: request.requestID, service: service)
        }

        if request.action == "delete" {
            return try delete(entity: entity, payload: payload, requestID: request.requestID, service: service)
        }

        let result: MinuteEntitySnapshot
        switch entity {
        case "area":
            guard let name = payload.name else {
                throw MinuteCommandAPIError.missingField("payload.name")
            }
            let area = try service.createArea(
                name: name,
                themeColor: payload.themeColor ?? "007AFF",
                iconName: payload.iconName ?? "folder",
                orderIndex: payload.orderIndex,
                sourceRequestID: request.requestID
            )
            result = MinuteEntitySnapshot(area: area)

        case "project":
            guard let name = payload.name else {
                throw MinuteCommandAPIError.missingField("payload.name")
            }
            let project = try service.createProject(
                name: name,
                areaName: payload.area,
                statusName: payload.status ?? ProjectStatus.active.rawValue,
                weeklyGoalSeconds: payload.weeklyGoalSeconds,
                orderIndex: payload.orderIndex,
                sourceRequestID: request.requestID
            )
            result = MinuteEntitySnapshot(project: project)

        case "task":
            guard let text = payload.text else {
                throw MinuteCommandAPIError.missingField("payload.text")
            }
            let task = try service.createTask(
                text: text,
                explicitProjectName: payload.project,
                dueDate: try payload.dueDate.map(parseDate),
                estimatedDuration: payload.durationSeconds,
                recurrenceInterval: payload.recurrence,
                orderIndex: payload.orderIndex,
                parseNaturalLanguage: payload.parseNaturalLanguage ?? true,
                sourceRequestID: request.requestID,
                notes: payload.notes,
                checklist: payload.checklist ?? []
            )
            result = MinuteEntitySnapshot(task: task)

        default:
            throw MinuteCommandAPIError.unsupportedEntity(entity)
        }

        try service.save()
        return MinuteCommandReceipt(
            version: 1,
            requestID: request.requestID,
            status: "success",
            entity: entity,
            entityID: result.id,
            displayName: result.name,
            message: "Created \(entity) '\(result.name)'.",
            processedAt: Date(),
            items: [result]
        )
    }

    private func list(
        entity: String,
        payload: MinuteCommandRequest.Payload,
        requestID: String,
        service: MinuteDataService
    ) throws -> MinuteCommandReceipt {
        let limit = min(max(payload.limit ?? 200, 1), 1_000)
        let items: [MinuteEntitySnapshot]

        switch entity {
        case "area":
            items = try service.fetchAreas()
                .sorted { ($0.orderIndex, $0.name.lowercased()) < ($1.orderIndex, $1.name.lowercased()) }
                .prefix(limit)
                .map(MinuteEntitySnapshot.init(area:))
        case "project":
            items = try service.fetchProjects()
                .filter { payload.area == nil || $0.area?.name.caseInsensitiveCompare(payload.area!) == .orderedSame }
                .filter { payload.status == nil || $0.status.rawValue == payload.status!.lowercased() }
                .sorted { ($0.orderIndex, $0.name.lowercased()) < ($1.orderIndex, $1.name.lowercased()) }
                .prefix(limit)
                .map(MinuteEntitySnapshot.init(project:))
        case "task":
            items = try service.fetchTasks()
                .filter { payload.project == nil || $0.project?.name.caseInsensitiveCompare(payload.project!) == .orderedSame }
                .filter { payload.completed == nil || $0.isCompleted == payload.completed }
                .sorted {
                    if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                    return $0.createdAt < $1.createdAt
                }
                .prefix(limit)
                .map(MinuteEntitySnapshot.init(task:))
        case "suggestion":
            items = try modelContext.fetch(FetchDescriptor<TaskSuggestion>())
                .filter { payload.status == nil || $0.status == payload.status }
                .sorted {
                    if $0.rank != $1.rank { return $0.rank < $1.rank }
                    return $0.generatedAt > $1.generatedAt
                }
                .prefix(limit)
                .map(MinuteEntitySnapshot.init(suggestion:))
        default:
            throw MinuteCommandAPIError.unsupportedEntity(entity)
        }

        return MinuteCommandReceipt(
            version: 1,
            requestID: requestID,
            status: "success",
            entity: entity,
            entityID: nil,
            displayName: nil,
            message: "Found \(items.count) \(entity)\(items.count == 1 ? "" : "s").",
            processedAt: Date(),
            items: items
        )
    }

    private func get(
        entity: String,
        payload: MinuteCommandRequest.Payload,
        requestID: String,
        service: MinuteDataService
    ) throws -> MinuteCommandReceipt {
        guard let identifier = payload.identifier else {
            throw MinuteCommandAPIError.missingField("payload.identifier")
        }
        let item = try snapshot(entity: entity, identifier: identifier, service: service)
        return MinuteCommandReceipt(
            version: 1,
            requestID: requestID,
            status: "success",
            entity: entity,
            entityID: item.id,
            displayName: item.name,
            message: "Found \(entity) '\(item.name)'.",
            processedAt: Date(),
            items: [item]
        )
    }

    private func update(
        entity: String,
        payload: MinuteCommandRequest.Payload,
        requestID: String,
        service: MinuteDataService
    ) throws -> MinuteCommandReceipt {
        guard let identifier = payload.identifier else {
            throw MinuteCommandAPIError.missingField("payload.identifier")
        }

        let item: MinuteEntitySnapshot
        switch entity {
        case "area":
            guard payload.name != nil
                || payload.themeColor != nil
                || payload.iconName != nil
                || payload.orderIndex != nil else {
                throw MinuteCommandAPIError.missingField("an editable area field")
            }
            let area = try service.resolveArea(identifier)
            try service.updateArea(
                area,
                name: payload.name,
                themeColor: payload.themeColor,
                iconName: payload.iconName,
                orderIndex: payload.orderIndex
            )
            item = MinuteEntitySnapshot(area: area)
        case "project":
            guard payload.name != nil
                || payload.area != nil
                || payload.status != nil
                || payload.weeklyGoalSeconds != nil
                || payload.clearWeeklyGoal == true
                || payload.orderIndex != nil else {
                throw MinuteCommandAPIError.missingField("an editable project field")
            }
            let project = try service.resolveProject(identifier)
            try service.updateProject(
                project,
                name: payload.name,
                areaName: payload.area,
                statusName: payload.status,
                weeklyGoalSeconds: payload.weeklyGoalSeconds,
                clearWeeklyGoal: payload.clearWeeklyGoal ?? false,
                orderIndex: payload.orderIndex
            )
            item = MinuteEntitySnapshot(project: project)
        case "task":
            guard payload.text != nil
                || payload.project != nil
                || payload.dueDate != nil
                || payload.clearDueDate == true
                || payload.durationSeconds != nil
                || payload.clearDuration == true
                || payload.recurrence != nil
                || payload.clearRecurrence == true
                || payload.completed != nil
                || payload.notes != nil
                || payload.clearNotes == true
                || payload.checklist != nil
                || payload.orderIndex != nil else {
                throw MinuteCommandAPIError.missingField("an editable task field")
            }
            let task = try service.resolveTask(identifier)
            try service.updateTask(
                task,
                title: payload.text,
                projectName: payload.project,
                dueDate: try payload.dueDate.map(parseDate),
                clearDueDate: payload.clearDueDate ?? false,
                estimatedDuration: payload.durationSeconds,
                clearDuration: payload.clearDuration ?? false,
                recurrenceInterval: payload.recurrence,
                clearRecurrence: payload.clearRecurrence ?? false,
                completed: payload.completed,
                orderIndex: payload.orderIndex,
                notes: payload.notes,
                clearNotes: payload.clearNotes ?? false,
                checklist: payload.checklist
            )
            item = MinuteEntitySnapshot(task: task)
        default:
            throw MinuteCommandAPIError.unsupportedEntity(entity)
        }

        try service.save()
        return MinuteCommandReceipt(
            version: 1,
            requestID: requestID,
            status: "success",
            entity: entity,
            entityID: item.id,
            displayName: item.name,
            message: "Updated \(entity) '\(item.name)'.",
            processedAt: Date(),
            items: [item]
        )
    }

    private func delete(
        entity: String,
        payload: MinuteCommandRequest.Payload,
        requestID: String,
        service: MinuteDataService
    ) throws -> MinuteCommandReceipt {
        guard let identifier = payload.identifier else {
            throw MinuteCommandAPIError.missingField("payload.identifier")
        }

        let item: MinuteEntitySnapshot
        switch entity {
        case "area":
            let area = try service.resolveArea(identifier)
            item = MinuteEntitySnapshot(area: area)
            try service.deleteArea(area, recursive: payload.recursive ?? false)
        case "project":
            let project = try service.resolveProject(identifier)
            item = MinuteEntitySnapshot(project: project)
            try service.deleteProject(project, recursive: payload.recursive ?? false)
        case "task":
            let task = try service.resolveTask(identifier)
            item = MinuteEntitySnapshot(task: task)
            service.deleteTask(task)
        default:
            throw MinuteCommandAPIError.unsupportedEntity(entity)
        }

        try service.save()
        return MinuteCommandReceipt(
            version: 1,
            requestID: requestID,
            status: "success",
            entity: entity,
            entityID: item.id,
            displayName: item.name,
            message: "Deleted \(entity) '\(item.name)'.",
            processedAt: Date(),
            items: [item]
        )
    }

    private func snapshot(
        entity: String,
        identifier: String,
        service: MinuteDataService
    ) throws -> MinuteEntitySnapshot {
        switch entity {
        case "area":
            return MinuteEntitySnapshot(area: try service.resolveArea(identifier))
        case "project":
            return MinuteEntitySnapshot(project: try service.resolveProject(identifier))
        case "task":
            return MinuteEntitySnapshot(task: try service.resolveTask(identifier))
        case "suggestion":
            return MinuteEntitySnapshot(
                suggestion: try TaskSuggestionService(modelContext: modelContext).resolve(identifier)
            )
        default:
            throw MinuteCommandAPIError.unsupportedEntity(entity)
        }
    }

    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw MinuteCommandAPIError.invalidDate(value)
    }

    private func receiptURL(requestID: String) throws -> URL {
        try MinuteCommandPaths.receipts(fileManager: fileManager)
            .appendingPathComponent(requestID)
            .appendingPathExtension("json")
    }

    private func write(receipt: MinuteCommandReceipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        try data.write(to: url, options: .atomic)
    }
}

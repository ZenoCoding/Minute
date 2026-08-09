//
//  MinuteDataModel.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import Foundation
import SwiftData

// MARK: - Goals & Tasks System

enum ProjectStatus: String, Codable {
    case active
    case backlog
    case completed
    case archived
}

@Model class Area {
    var id: UUID = UUID()
    var sourceRequestID: String?
    var name: String
    var themeColor: String // Hex string
    var iconName: String   // SF Symbol
    var orderIndex: Int = 0
    var createdAt: Date
    
    // CloudKit requires relationships to be optional. Keep the old
    // `projects` API as a computed compatibility facade so existing macOS
    // views continue to treat an absent relationship as an empty collection.
    @Relationship(deleteRule: .cascade, originalName: "projects", inverse: \Project.area)
    fileprivate var projectsStorage: [Project]? = nil

    var projects: [Project] {
        get { projectsStorage ?? [] }
        set { projectsStorage = newValue }
    }
    
    init(name: String, themeColor: String = "007AFF", iconName: String = "folder", orderIndex: Int = 0, createdAt: Date = Date()) {
        self.name = name
        self.themeColor = themeColor
        self.iconName = iconName
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }
}

@Model class Project {
    var id: UUID = UUID()
    var sourceRequestID: String?
    var name: String
    var status: ProjectStatus
    var weeklyGoalSeconds: TimeInterval?
    var orderIndex: Int = 0
    var createdAt: Date
    
    // Relationships
    var area: Area?
    
    @Relationship(deleteRule: .cascade, originalName: "tasks", inverse: \TaskItem.project)
    fileprivate var tasksStorage: [TaskItem]? = nil

    var tasks: [TaskItem] {
        get { tasksStorage ?? [] }
        set { tasksStorage = newValue }
    }
    
    init(name: String, status: ProjectStatus = .active, weeklyGoalSeconds: TimeInterval? = nil, orderIndex: Int = 0, area: Area? = nil) {
        self.name = name
        self.status = status
        self.weeklyGoalSeconds = weeklyGoalSeconds
        self.orderIndex = orderIndex
        self.area = area
        self.createdAt = Date()
    }
}

@Model class TaskItem {
    var id: UUID = UUID()
    var sourceRequestID: String?
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var orderIndex: Int = 0
    var createdAt: Date
    
    var project: Project?
    
    // Metadata
    var estimatedDuration: TimeInterval?
    var dueDate: Date?
    var notes: String? = nil
    var workStartedAt: Date? = nil

    // CloudKit-compatible optional relationship. Existing callers use the
    // sorted facade, which also presents an absent relationship as empty.
    @Relationship(deleteRule: .cascade, originalName: "checklist", inverse: \TaskChecklistItem.task)
    fileprivate var checklistStorage: [TaskChecklistItem]? = nil

    var checklist: [TaskChecklistItem] {
        get {
            (checklistStorage ?? []).sorted {
                if $0.orderIndex != $1.orderIndex { return $0.orderIndex < $1.orderIndex }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        set { checklistStorage = newValue }
    }
    
    // Recurrence (Habits)
    var isRecurring: Bool = false
    var recurrenceInterval: String? // "daily", "weekly", etc.
    
    init(title: String, orderIndex: Int = 0, project: Project? = nil, estimatedDuration: TimeInterval? = nil, dueDate: Date? = nil, notes: String? = nil, workStartedAt: Date? = nil) {
        self.title = title
        self.isCompleted = false
        self.orderIndex = orderIndex
        self.createdAt = Date()
        self.project = project
        self.estimatedDuration = estimatedDuration
        self.dueDate = dueDate
        self.notes = notes
        self.workStartedAt = workStartedAt
    }
}

@Model class TaskChecklistItem {
    var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var orderIndex: Int = 0
    var createdAt: Date = Date()

    // The inverse is optional for SwiftData and CloudKit compatibility.
    var task: TaskItem? = nil

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        orderIndex: Int = 0,
        createdAt: Date = Date(),
        task: TaskItem? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = isCompleted ? (completedAt ?? Date()) : nil
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.task = task
    }
}

/// The shared, shallow value used by editors and the local command API when
/// replacing a task's checklist.
struct TaskChecklistDraft: Codable, Equatable {
    var title: String
    var isCompleted: Bool

    init(title: String, isCompleted: Bool = false) {
        self.title = title
        self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}

@Model final class TaskSuggestion {
    var id: UUID = UUID()
    var sourceRequestID: String?
    var fingerprint: String = ""
    var title: String = ""
    var sourceType: String = "idea"
    var sourceLabel: String = "Idea"
    var sourceURL: String?
    var evidenceSnippet: String?
    var reason: String?
    var inferredProjectName: String?
    var dueDate: Date?
    var confidence: Double = 0
    var rank: Int = 0
    var status: String = "pending"
    var generatedAt: Date = Date()
    var acceptedTaskID: UUID?

    init(
        fingerprint: String,
        title: String,
        sourceType: String,
        sourceLabel: String,
        sourceURL: String? = nil,
        evidenceSnippet: String? = nil,
        reason: String? = nil,
        inferredProjectName: String? = nil,
        dueDate: Date? = nil,
        confidence: Double = 0,
        rank: Int = 0,
        sourceRequestID: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.title = title
        self.sourceType = sourceType
        self.sourceLabel = sourceLabel
        self.sourceURL = sourceURL
        self.evidenceSnippet = evidenceSnippet
        self.reason = reason
        self.inferredProjectName = inferredProjectName
        self.dueDate = dueDate
        self.confidence = confidence
        self.rank = rank
        self.sourceRequestID = sourceRequestID
    }
}

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
    
    @Relationship(deleteRule: .cascade, inverse: \Project.area)
    var projects: [Project] = []
    
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
    
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []
    
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
    
    // Recurrence (Habits)
    var isRecurring: Bool = false
    var recurrenceInterval: String? // "daily", "weekly", etc.
    
    init(title: String, orderIndex: Int = 0, project: Project? = nil, estimatedDuration: TimeInterval? = nil, dueDate: Date? = nil) {
        self.title = title
        self.isCompleted = false
        self.orderIndex = orderIndex
        self.createdAt = Date()
        self.project = project
        self.estimatedDuration = estimatedDuration
        self.dueDate = dueDate
    }
}

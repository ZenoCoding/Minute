//
//  MinuteDataModel.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import Foundation
import SwiftData

// MARK: - Enums

enum TrackingState: String, Codable {
    case active
    case idle
    case away
}

enum ActivityType: String, Codable, CaseIterable {
    case focusedWork = "Focused Work"
    case communication = "Communication"
    case browser = "Browser"
    case entertainment = "Entertainment"
    case admin = "Admin"
    case referenceLearning = "Reference"
    case idle = "Idle"
    case away = "Away"
    case unknown = "Unknown"
    case meta = "Meta"
}

/// Why a segment is marked "Unknown"
enum UnknownReason: String, Codable {
    case unmappedApp = "Unmapped app"
    case ambiguousApp = "Ambiguous app"
    case idle = "Idle/Away"
}

// MARK: - Loss Minutes Enums

/// Type of loss event detected
enum LossType: String, Codable, CaseIterable {
    case idle = "Idle Gap"
    case distraction = "Distraction"
    case switching = "Switching Storm"
    case recovery = "Recovery Delay"
    case friction = "Fragmentation"
}

/// Extension to classify surfaces as productive/unproductive
extension ActivityType {
    var isProductive: Bool {
        switch self {
        case .focusedWork, .admin, .referenceLearning:
            return true
        default:
            return false
        }
    }
    
    var isDistraction: Bool {
        switch self {
        case .entertainment:
            return true
        case .browser, .communication:
            return false // Ambiguous by default
        default:
            return false
        }
    }
    
    var isNeutral: Bool {
        switch self {
        case .idle, .away, .meta, .unknown:
            return true
        default:
            return false
        }
    }
}

// MARK: - Segment (Raw observation)

@Model
final class Segment {
    var id: UUID = UUID()
    var startTimestamp: Date
    var endTimestamp: Date?
    var bundleID: String
    var appName: String
    var state: TrackingState
    var idleSecondsAtEnd: Double
    
    // Auto-classification
    var autoActivityType: ActivityType
    var autoConfidence: Double // 0.0 - 1.0
    var unknownReason: UnknownReason?
    
    // Workflow state
    var needsReview: Bool
    
    // Session relationship
    var session: Session?
    
    // User label overlay
    @Relationship(deleteRule: .cascade, inverse: \ActivityLabel.segment)
    var userLabel: ActivityLabel?
    
    init(startTimestamp: Date, 
         bundleID: String, 
         appName: String, 
         state: TrackingState, 
         autoActivityType: ActivityType = .unknown, 
         autoConfidence: Double = 0.0,
         unknownReason: UnknownReason? = nil) {
        self.startTimestamp = startTimestamp
        self.bundleID = bundleID
        self.appName = appName
        self.state = state
        self.idleSecondsAtEnd = 0
        self.autoActivityType = autoActivityType
        self.autoConfidence = autoConfidence
        self.unknownReason = unknownReason
        self.needsReview = true
    }
    
    var duration: TimeInterval {
        guard let end = endTimestamp else { return Date().timeIntervalSince(startTimestamp) }
        return end.timeIntervalSince(startTimestamp)
    }
}

// MARK: - FocusGroup (AI-managed task container)

@Model
final class FocusGroup {
    var id: UUID = UUID()
    var name: String                     // "Physics Study", "Vibe Coding"
    var icon: String?                    // SF Symbol name (e.g. "studentdesk", "laptopcomputer")
    var date: Date                       // Day this group belongs to
    var createdAt: Date
    var lastActiveAt: Date
    
    // Sessions in this group
    @Relationship(deleteRule: .nullify, inverse: \Session.focusGroup)
    var sessions: [Session] = []
    
    init(name: String, icon: String? = nil, date: Date = Date()) {
        self.name = name
        self.icon = icon
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
    
    /// Total duration of productive sessions
    var productiveTime: TimeInterval {
        sessions.filter { !$0.isGroupDistraction }.reduce(0) { $0 + $1.duration }
    }
    
    /// Total distraction time within this group
    var distractionTime: TimeInterval {
        sessions.filter { $0.isGroupDistraction }.reduce(0) { $0 + $1.duration }
    }
    
    /// Session count
    var sessionCount: Int { sessions.count }
}

// MARK: - Goals & Tasks System

enum ProjectStatus: String, Codable {
    case active
    case backlog
    case completed
    case archived
}

@Model class Area {
    var id: UUID = UUID()
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
    var name: String
    var status: ProjectStatus
    var weeklyGoalSeconds: TimeInterval?
    var orderIndex: Int = 0
    var createdAt: Date
    
    // Relationships
    var area: Area?
    
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []
    
    @Relationship(deleteRule: .nullify, inverse: \Session.project)
    var sessions: [Session] = []
    
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
    
    // Tracking
    @Relationship(deleteRule: .nullify)
    var sessions: [Session] = []
    
    var timeSpent: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    
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

// MARK: - Session (Merged block for UI)

@Model
final class Session {
    var id: UUID = UUID()
    var startTimestamp: Date
    var endTimestamp: Date?
    var bundleID: String
    var appName: String
    var state: TrackingState
    
    // Classification (derived from segments or user-set)
    var activityType: ActivityType
    var confidence: Double
    var unknownReason: UnknownReason?
    var needsReview: Bool
    
    // Merge tracking
    var microInterruptions: Int = 0
    
    // Duration tracking across interruptions
    var accumulatedDuration: TimeInterval = 0
    var lastResumedAt: Date?
    
    // Browser Context (from extension)
    var browserDomain: String?          // Primary domain (most time spent)
    var browserTitle: String?           // Title from active tab
    
    // Task Labeling
    var inferredTask: String?           // Suggested task label
    var userTaskLabel: String?          // User-provided task override
    
    // Focus Group (AI-managed)
    var focusGroup: FocusGroup?         // Parent focus group
    var project: Project?               // Link to intentional goal
    var isGroupDistraction: Bool = false // Marked as distraction within group
    
    // Task Link (Direct Tracking)
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.sessions)
    var task: TaskItem?

    
    // Child segments
    @Relationship(deleteRule: .cascade) var segments: [Segment] = []
    
    // Browser sub-sessions (domain visits within this session)
    @Relationship(deleteRule: .cascade) var browserVisits: [BrowserVisit] = []
    
    init(startTimestamp: Date,
         bundleID: String,
         appName: String,
         state: TrackingState,
         activityType: ActivityType = .unknown,
         confidence: Double = 0.0,
         unknownReason: UnknownReason? = nil) {
        self.startTimestamp = startTimestamp
        self.bundleID = bundleID
        self.appName = appName
        self.state = state
        self.activityType = activityType
        self.confidence = confidence
        self.unknownReason = unknownReason
        self.needsReview = activityType == .unknown || confidence < 0.8
        self.lastResumedAt = nil
    }
    
    var duration: TimeInterval {
        if endTimestamp != nil {
            // Session is closed - accumulatedDuration IS the total
            // (We accumulate the final segment when closing)
            return accumulatedDuration > 0 ? accumulatedDuration : (endTimestamp!.timeIntervalSince(startTimestamp))
        } else {
            // Session is active - accumulated + current segment
            let activeStart = lastResumedAt ?? startTimestamp
            return accumulatedDuration + Date().timeIntervalSince(activeStart)
        }
    }
    
    /// The effective task label (user override or inferred)
    var taskLabel: String? {
        userTaskLabel ?? inferredTask
    }
}

// MARK: - ActivityLabel (User overlay)

@Model
final class ActivityLabel {
    var assignedDate: Date
    var projectLabel: String
    var activityTypeOverride: ActivityType?
    var notes: String?
    var segment: Segment?
    
    init(projectLabel: String, activityTypeOverride: ActivityType? = nil, notes: String? = nil) {
        self.assignedDate = Date()
        self.projectLabel = projectLabel
        self.activityTypeOverride = activityTypeOverride
        self.notes = notes
    }
}

// MARK: - AppCategoryRule (User-defined mapping)

@Model
final class AppCategoryRule {
    @Attribute(.unique) var bundleID: String
    var assignedActivityType: ActivityType
    var isAmbiguous: Bool
    var isIgnored: Bool
    
    init(bundleID: String, assignedActivityType: ActivityType, isAmbiguous: Bool = false) {
        self.bundleID = bundleID
        self.assignedActivityType = assignedActivityType
        self.isAmbiguous = isAmbiguous
        self.isIgnored = false
    }
}

// MARK: - Cluster (Task grouping for review)

/// A cluster groups adjacent sessions that represent a "task attempt"
@Model
final class Cluster {
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var suggestedLabel: String?
    var userLabel: String?
    var confidence: Double
    var labelSource: String?  // "rule", "user", "llm"
    
    // Computed from sessions
    var primaryApp: String?
    var primaryDomain: String?
    
    // Sessions in this cluster (stored as IDs to avoid circular refs)
    var sessionIDs: [UUID] = []
    
    init(startTime: Date, endTime: Date, suggestedLabel: String? = nil, confidence: Double = 0) {
        self.startTime = startTime
        self.endTime = endTime
        self.suggestedLabel = suggestedLabel
        self.confidence = confidence
    }
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    /// The effective label (user override or suggested)
    var label: String? {
        userLabel ?? suggestedLabel
    }
}

// MARK: - DomainRule (Browser domain mapping)

@Model
final class DomainRule {
    @Attribute(.unique) var domain: String
    var assignedActivityType: ActivityType
    var taskLabel: String?
    var isDistraction: Bool
    
    init(domain: String, activityType: ActivityType, taskLabel: String? = nil, isDistraction: Bool = false) {
        self.domain = domain
        self.assignedActivityType = activityType
        self.taskLabel = taskLabel
        self.isDistraction = isDistraction
    }
}

// MARK: - BrowserVisit (Sub-session within a browser session)

@Model
final class BrowserVisit {
    var id: UUID = UUID()
    var startTimestamp: Date
    var endTimestamp: Date?
    var domain: String
    var title: String?
    var isDistraction: Bool
    
    // Rich context for AI task inference
    var path: String?
    var pageDescription: String?
    var ogType: String?
    var contentSnippet: String?
    
    // Parent session
    var session: Session?
    
    init(startTimestamp: Date, domain: String, title: String? = nil, isDistraction: Bool = false) {
        self.startTimestamp = startTimestamp
        self.domain = domain
        self.title = title
        self.isDistraction = isDistraction
    }
    
    /// Initialize with rich context
    init(startTimestamp: Date, domain: String, context: BrowserContext?, isDistraction: Bool = false) {
        self.startTimestamp = startTimestamp
        self.domain = domain
        self.title = context?.title
        self.isDistraction = isDistraction
        self.path = context?.path
        self.pageDescription = context?.description ?? context?.ogDescription
        self.ogType = context?.ogType
        self.contentSnippet = context?.contentSnippet
    }
    
    var duration: TimeInterval {
        let end = endTimestamp ?? Date()
        return end.timeIntervalSince(startTimestamp)
    }
}

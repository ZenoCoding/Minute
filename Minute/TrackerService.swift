//
//  TrackerService.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import Foundation
import AppKit
import SwiftData
import Combine

@MainActor
class TrackerService: ObservableObject {
    private var modelContext: ModelContext
    private var idleMonitor: IdleMonitor
    private var browserBridge: BrowserBridge
    private var focusGroupService: FocusGroupService
    
    // Configuration
    private let commitThreshold: TimeInterval = 2.0  // Don't commit segments shorter than this
    private let mergeThreshold: TimeInterval = 30.0  // Merge if switch away and back within this
    
    // Self-exclusion: these apps are tracked as .meta and hidden by default
    private let hiddenBundleIDs: Set<String> = [
        "com.tychoyoung.Minute",
        "com.apple.systempreferences",
        "com.apple.SystemPreferences"
    ]
    
    // State
    @Published var currentSession: Session?
    @Published var pendingSegment: PendingSegment?
    @Published var showMetaSessions: Bool = false  // Toggle to show/hide meta sessions
    @Published var activeTask: TaskItem? // The user's declared intent
    
    // Recent history for merge detection
    private var recentSessions: [(bundleID: String, endTime: Date, session: Session)] = []
    
    // Observers
    private var workspaceObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    
    /// Pending segment before commit threshold is met
    struct PendingSegment {
        let bundleID: String
        let appName: String
        let state: TrackingState
        let startTime: Date
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.idleMonitor = IdleMonitor()
        self.browserBridge = BrowserBridge()
        self.focusGroupService = FocusGroupService()
        
        seedDefaultMappings()
        cleanupOrphanedSessions()
        setupObservers()
    }
    
    func startTracking() {
        print("TrackerService: Started")
        handleAppChange()
    }
    
    // MARK: - Task Control
    
    func startTask(_ task: TaskItem) {
        guard activeTask?.id != task.id else { return }
        print("TrackerService: Switching focus to task '\(task.title)'")
        
        // 1. Close current session (so we can start a new one linked to this task)
        // If we just attach the CURRENT session to the new task, we might retrospectively re-label
        // work that wasn't actually for this task.
        // SAFE APPROACH: Close current session, start new one (even if same app).
        
        // Preserve current app state
        let currentApp = currentSession?.bundleID
        let currentVisit = currentBrowserVisit
        
        closeCurrentSession()
        
        // 2. Set Active Task
        activeTask = task
        
        // 3. Re-trigger app change to start new session
        // If we were in an app, this will create a new session for it immediately.
        // We need to ensure handleAppChange picks up the new activeTask.
        // Since activeTask is set, the NEXT session created by commitPendingSegment will pick it up.
        
        handleAppChange()
    }
    
    func stopCurrentTask() {
        guard activeTask != nil else { return }
        print("TrackerService: Stopping active task")
        
        closeCurrentSession()
        activeTask = nil
        handleAppChange()
    }
    
    /// Close any sessions that were left open from a previous run
    private func cleanupOrphanedSessions() {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.endTimestamp == nil }
        )
        
        guard let orphans = try? modelContext.fetch(descriptor) else { return }
        
        for session in orphans {
            // Close the session at its last known time
            let closeTime = session.lastResumedAt ?? session.startTimestamp
            session.endTimestamp = closeTime.addingTimeInterval(session.accumulatedDuration > 0 ? 0 : 1)
            
            // If no accumulated duration, estimate from start
            if session.accumulatedDuration == 0 {
                session.accumulatedDuration = session.endTimestamp!.timeIntervalSince(session.startTimestamp)
            }
        }
        
        if !orphans.isEmpty {
            try? modelContext.save()
            print("TrackerService: Closed \(orphans.count) orphaned sessions from previous run")
        }
    }
    
    // MARK: - Task Correction
    
    func setTaskLabel(_ label: String, for session: Session) {
        session.userTaskLabel = label
        try? modelContext.save()
    }
    
    // MARK: - Seed Default Mappings
    
    private func seedDefaultMappings() {
        let defaults: [(String, ActivityType, Bool)] = [
            // Focused Work (confident)
            ("com.apple.dt.Xcode", .focusedWork, false),
            ("com.googlecode.iterm2", .focusedWork, false),
            ("com.apple.Terminal", .focusedWork, false),
            ("com.microsoft.VSCode", .focusedWork, false),
            ("com.sublimetext.4", .focusedWork, false),
            ("com.jetbrains.intellij", .focusedWork, false),
            
            // Browsers (ambiguous - need extension)
            ("com.apple.Safari", .browser, true),
            ("com.google.Chrome", .browser, true),
            ("org.mozilla.firefox", .browser, true),
            ("com.brave.Browser", .browser, true),
            ("company.thebrowser.Browser", .browser, true),
            
            // Communication (ambiguous - could be work or social)
            ("com.hnc.Discord", .communication, true),
            ("com.tinyspeck.slackmacgap", .communication, true),
            ("com.apple.MobileSMS", .communication, true),
            ("com.apple.mail", .communication, false),
            ("us.zoom.xos", .communication, false),
            
            // Entertainment (confident)
            ("com.spotify.client", .entertainment, false),
            ("com.apple.Music", .entertainment, false),
            ("com.apple.TV", .entertainment, false),
            
            // Admin (confident)
            ("com.apple.finder", .admin, false),
            ("com.apple.systempreferences", .admin, false),
            ("com.apple.ActivityMonitor", .admin, false),
            
            // Meta (ignore Minute itself)
            ("com.tycho.Minute", .meta, false),
        ]
        
        for (bundleID, activityType, isAmbiguous) in defaults {
            let descriptor = FetchDescriptor<AppCategoryRule>(predicate: #Predicate { $0.bundleID == bundleID })
            if (try? modelContext.fetch(descriptor).first) == nil {
                let rule = AppCategoryRule(bundleID: bundleID, assignedActivityType: activityType, isAmbiguous: isAmbiguous)
                modelContext.insert(rule)
            }
        }
        try? modelContext.save()
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        workspaceObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleAppChange()
            }
        }
        
        idleMonitor.$isIdle
            .removeDuplicates()
            .sink { [weak self] isIdle in
                self?.handleIdleChange(isIdle: isIdle)
            }
            .store(in: &cancellables)
            
        idleMonitor.$isAway
            .removeDuplicates()
            .sink { [weak self] isAway in
                self?.handleAwayChange(isAway: isAway)
            }
            .store(in: &cancellables)
        
        // Subscribe to browser domain changes
        browserBridge.onDomainChange = { [weak self] oldDomain, newDomain, title in
            self?.handleDomainChange(from: oldDomain, to: newDomain, title: title)
        }
    }
    
    // MARK: - Browser Domain Changes
    
    private var currentBrowserVisit: BrowserVisit?
    
    private func handleDomainChange(from oldDomain: String, to newDomain: String, title: String?) {
        // We received a domain change from the extension, so this IS a browser session
        guard let session = currentSession else { return }
        
        // Close the previous visit
        if let visit = currentBrowserVisit {
            visit.endTimestamp = Date()
        }
        
        // Get rich context for AI inference
        let richContext = browserBridge.getRichContext()
        
        // SPLIT: Close current session and create new one for the new domain
        // This enables per-domain AI classification
        closeCurrentSession()
        
        let bundleID = session.bundleID
        let appName = session.appName
        let state = session.state
        
        // Create new session for new domain
        let newSession = Session(
            startTimestamp: Date(),
            bundleID: bundleID,
            appName: appName,
            state: state,
            activityType: .browser,
            confidence: 1.0
        )
        
        // Link to active task if present
        if let task = activeTask {
            newSession.task = task
        }
        
        newSession.browserDomain = newDomain
        newSession.browserTitle = title
        
        // Check if new domain is a distraction
        let isDistraction = DistractionRules.isDistraction(domain: newDomain)
        
        // Create initial browser visit with rich context
        let visit = BrowserVisit(
            startTimestamp: Date(),
            domain: newDomain,
            context: richContext,
            isDistraction: isDistraction
        )
        visit.session = newSession
        newSession.browserVisits.append(visit)
        
        modelContext.insert(newSession)
        modelContext.insert(visit)
        currentSession = newSession
        currentBrowserVisit = visit
        
        let snippetInfo = richContext?.contentSnippet != nil ? " (\(richContext!.contentSnippet!.prefix(50))...)" : ""
        print("TrackerService: New browser session for \(newDomain)\(snippetInfo)")
        
        // Classify into focus group (async)
        Task { @MainActor in
            await focusGroupService.classifySession(newSession, modelContext: modelContext)
        }
        
        try? modelContext.save()
    }
    
    // MARK: - App Changes
    
    private func handleAppChange() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleID = app.bundleIdentifier ?? "unknown.bundle.id"
        let appName = app.localizedName ?? "Unknown App"
        let state: TrackingState = idleMonitor.isAway ? .away : (idleMonitor.isIdle ? .idle : .active)
        
        // Same app? Just update state if needed
        if let current = currentSession, current.bundleID == bundleID && current.state == state {
            return
        }
        
        // FIRST: Check for merge opportunity BEFORE committing any pending segment
        // This prevents creating a session for the interruption when we're just merging back
        if let mergeTarget = findMergeTarget(bundleID: bundleID, state: state) {
            print("TrackerService: Merging back into session \(mergeTarget.appName)")
            
            // Discard the pending segment (the brief interruption)
            if let pending = pendingSegment {
                print("TrackerService: Discarding interruption \(pending.appName) for merge")
            }
            pendingSegment = nil
            
            mergeTarget.microInterruptions += 1
            mergeTarget.endTimestamp = nil  // Re-open the session
            mergeTarget.lastResumedAt = Date()  // Mark when we resumed
            currentSession = mergeTarget
            
            // Remove from recent list since we're back in it
            recentSessions.removeAll { $0.session.id == mergeTarget.id }
            return
        }
        
        // No merge - check pending segment for commit threshold
        if let pending = pendingSegment {
            let elapsed = Date().timeIntervalSince(pending.startTime)
            if elapsed >= commitThreshold {
                commitPendingSegment()
            } else {
                // Discard - didn't meet threshold
                print("TrackerService: Discarded pending segment \(pending.appName) (too short: \(String(format: "%.1f", elapsed))s)")
            }
            pendingSegment = nil
        }
        
        // Start new pending segment
        pendingSegment = PendingSegment(bundleID: bundleID, appName: appName, state: state, startTime: Date())
        
        // Schedule commit check
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .seconds(self.commitThreshold + 0.1))
            self.checkPendingCommit()
        }
    }
    
    private func checkPendingCommit() {
        guard let pending = pendingSegment else { return }
        
        // Still the same pending segment?
        let elapsed = Date().timeIntervalSince(pending.startTime)
        if elapsed >= commitThreshold {
            commitPendingSegment()
        }
    }
    
    private func commitPendingSegment() {
        guard let pending = pendingSegment else { return }
        
        // Close current session first
        closeCurrentSession()
        
        // Create new session
        let (activityType, confidence, reason) = classify(bundleID: pending.bundleID, state: pending.state)
        
        let session = Session(
            startTimestamp: pending.startTime,
            bundleID: pending.bundleID,
            appName: pending.appName,
            state: pending.state,
            activityType: activityType,
            confidence: confidence,
            unknownReason: reason
        )
        
        // Link to active task if present
        if let task = activeTask {
            session.task = task
        }
        
        // Capture browser context if this is a browser session
        if activityType == .browser {
            let (domain, title) = browserBridge.getCurrentContext()
            session.browserDomain = domain
            session.browserTitle = title
            
            // Create initial browser visit
            if let domain = domain {
                let isDistraction = DistractionRules.isDistraction(domain: domain)
                let visit = BrowserVisit(
                    startTimestamp: pending.startTime,
                    domain: domain,
                    title: title,
                    isDistraction: isDistraction
                )
                visit.session = session
                session.browserVisits.append(visit)
                modelContext.insert(visit)
                currentBrowserVisit = visit
                
                print("TrackerService: Browser context - \(domain)")
            }
        }
        
        modelContext.insert(session)
        currentSession = session
        pendingSegment = nil
        
        let domainInfo = session.browserDomain.map { " [\($0)]" } ?? ""
        print("TrackerService: Committed session \(pending.appName) -> \(activityType.rawValue)\(domainInfo)")
        
        // Classify into focus group (async, non-blocking)
        if activityType != .meta {
            Task { @MainActor in
                await focusGroupService.classifySession(session, modelContext: modelContext)
            }
        }
    }
    
    private func closeCurrentSession() {
        guard let session = currentSession else { return }
        
        // Close current browser visit if any
        if let visit = currentBrowserVisit {
            visit.endTimestamp = Date()
            currentBrowserVisit = nil
            
            // Update primary domain to the one with most time spent
            if !session.browserVisits.isEmpty {
                let sortedVisits = session.browserVisits.sorted { $0.duration > $1.duration }
                session.browserDomain = sortedVisits.first?.domain
                session.browserTitle = sortedVisits.first?.title
            }
        }
        
        // Accumulate the duration from this active segment before closing
        let activeStart = session.lastResumedAt ?? session.startTimestamp
        session.accumulatedDuration += Date().timeIntervalSince(activeStart)
        session.endTimestamp = Date()
        session.lastResumedAt = nil  // Clear resume marker
        
        // Discard very short sessions (< 2 seconds)
        if session.duration < commitThreshold {
            modelContext.delete(session)
            currentSession = nil
            print("TrackerService: Discarded short session \(session.appName) (\(String(format: "%.1f", session.duration))s)")
            return
        }
        
        // Add to recent sessions for merge detection (only non-Meta)
        if session.activityType != .meta {
            recentSessions.append((session.bundleID, Date(), session))
        }
        
        // Prune old entries
        let cutoff = Date().addingTimeInterval(-mergeThreshold)
        recentSessions.removeAll { $0.endTime < cutoff }
        
        try? modelContext.save()
        currentSession = nil
        print("TrackerService: Closed session \(session.appName) (duration: \(Int(session.duration))s)")
    }
    
    private func findMergeTarget(bundleID: String, state: TrackingState) -> Session? {
        let cutoff = Date().addingTimeInterval(-mergeThreshold)
        
        for recent in recentSessions.reversed() {
            if recent.bundleID == bundleID && recent.endTime > cutoff && recent.session.state == state {
                return recent.session
            }
        }
        return nil
    }
    
    // MARK: - Idle/Away Changes
    
    private func handleIdleChange(isIdle: Bool) {
        guard currentSession != nil || pendingSegment != nil else { return }
        
        if isIdle {
            handleAppChange() // Will create idle segment
        } else {
            handleAppChange() // Will create active segment
        }
    }
    
    private func handleAwayChange(isAway: Bool) {
        guard currentSession != nil || pendingSegment != nil else { return }
        handleAppChange()
    }
    
    // MARK: - Classification
    
    private func classify(bundleID: String, state: TrackingState) -> (ActivityType, Double, UnknownReason?) {
        // Idle/Away override
        if state == .idle {
            return (.idle, 1.0, .idle)
        }
        if state == .away {
            return (.away, 1.0, .idle)
        }
        
        // Check user rules first
        let descriptor = FetchDescriptor<AppCategoryRule>(predicate: #Predicate { $0.bundleID == bundleID })
        if let rule = try? modelContext.fetch(descriptor).first {
            if rule.isAmbiguous {
                return (rule.assignedActivityType, 0.5, .ambiguousApp)
            } else {
                return (rule.assignedActivityType, 1.0, nil)
            }
        }
        
        // Unmapped
        return (.unknown, 0.0, .unmappedApp)
    }
    
    // MARK: - Public API for UI
    
    func mapApp(bundleID: String, to activityType: ActivityType, isAmbiguous: Bool = false) {
        // Delete existing rule if any
        let descriptor = FetchDescriptor<AppCategoryRule>(predicate: #Predicate { $0.bundleID == bundleID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        
        // Create new rule
        let rule = AppCategoryRule(bundleID: bundleID, assignedActivityType: activityType, isAmbiguous: isAmbiguous)
        modelContext.insert(rule)
        
        // Update all existing sessions with this bundleID
        let sessionDescriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.bundleID == bundleID })
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            for session in sessions {
                session.activityType = activityType
                session.confidence = isAmbiguous ? 0.5 : 1.0
                session.unknownReason = isAmbiguous ? .ambiguousApp : nil
                session.needsReview = isAmbiguous
            }
        }
        
        try? modelContext.save()
        print("TrackerService: Mapped \(bundleID) -> \(activityType.rawValue)")
    }
}

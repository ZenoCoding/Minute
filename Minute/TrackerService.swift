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
        startHeartbeat()
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
        // Preserve current app state
        _ = currentSession?.bundleID
        _ = currentBrowserVisit
        
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
            // SAFE FALLBACK:
            // If the app crashed, we don't know when it ended. 
            // We assume it ended reasonably close to the last checkpoint.
            // If we have accumulated duration (from heartbeat), we trust that.
            // If we have a lastResumeAt, we add a small buffer (e.g. 1 min) and close it there.
            
            let lastActive = session.lastResumedAt ?? session.startTimestamp
            
            // If it's been incomplete for > 24 hours, it's definitely stale.
            // But even if it was 5 mins ago, we shouldn't assume it lasted until now.
            // Let's cap the "lost" segment at 60 seconds (heartbeat interval + buffer).
            
            session.accumulatedDuration += 60 // Assume 1 min of life after last checkpoint
            session.endTimestamp = lastActive.addingTimeInterval(60)
            session.lastResumedAt = nil
        }
        
        if !orphans.isEmpty {
            try? modelContext.save()
            print("TrackerService: Closed \(orphans.count) orphaned sessions from previous run (safely capped)")
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
            // --- Focused Work ---
            ("com.apple.dt.Xcode", .focusedWork, false),
            ("com.microsoft.VSCode", .focusedWork, false),
            ("com.googlecode.iterm2", .focusedWork, false),
            ("com.apple.Terminal", .focusedWork, false),
            ("com.sublimetext.4", .focusedWork, false),
            ("com.jetbrains.intellij", .focusedWork, false),
            ("com.jetbrains.pycharm", .focusedWork, false),
            ("com.jetbrains.webstorm", .focusedWork, false),
            ("com.panic.Nova", .focusedWork, false),
            ("com.github.GitHubClient", .focusedWork, false),
            ("com.apple.iWork.Pages", .focusedWork, false),
            ("com.apple.iWork.Keynote", .focusedWork, false),
            ("com.apple.iWork.Numbers", .focusedWork, false),
            ("notion.id", .focusedWork, false),
            ("com.microsoft.Word", .focusedWork, false),
            ("com.microsoft.Excel", .focusedWork, false),
            ("com.microsoft.Powerpoint", .focusedWork, false),
            ("com.figma.Desktop", .focusedWork, false),
            ("com.adobe.Photoshop", .focusedWork, false),
            ("com.adobe.illustrator", .focusedWork, false),
            ("com.adobe.LightroomClassicCC7", .focusedWork, false),
            ("com.maxon.cinema4d", .focusedWork, false),
            ("com.blender.blender", .focusedWork, false),
            
            // --- Browsers (Ambiguous) ---
            ("com.apple.Safari", .browser, true),
            ("com.google.Chrome", .browser, true),
            ("org.mozilla.firefox", .browser, true),
            ("com.brave.Browser", .browser, true),
            ("company.thebrowser.Browser", .browser, true),
            ("com.opera.Opera", .browser, true),
            ("com.microsoft.edgemac", .browser, true),
            
            // --- Communication ---
            ("com.hnc.Discord", .communication, true),
            ("com.tinyspeck.slackmacgap", .communication, true),
            ("com.apple.MobileSMS", .communication, true),
            ("com.apple.mail", .communication, false),
            ("us.zoom.xos", .communication, false),
            ("com.microsoft.teams", .communication, false),
            ("com.telegram.desktop", .communication, true),
            ("ru.keepcoder.Telegram", .communication, true),
            ("com.whatsapp.desktop", .communication, true),
            ("com.apple.iCal", .communication, false), // Scheduling often involves comms
            ("com.flexibits.fantastical2.mac", .communication, false),
            ("readdle.spark.mac", .communication, false),

            // --- Entertainment ---
            ("com.spotify.client", .entertainment, false),
            ("com.apple.Music", .entertainment, false),
            ("com.apple.TV", .entertainment, false),
            ("com.valve.steam", .entertainment, false),
            ("com.apple.podcasts", .entertainment, false),
            
            // --- Admin / Utilities ---
            ("com.apple.finder", .admin, false),
            ("com.apple.systempreferences", .admin, false),
            ("com.apple.ActivityMonitor", .admin, false),
            ("com.apple.AppStore", .admin, false),
            ("com.apple.Notes", .focusedWork, true), // Ambiguous: could be personal list or work notes
            ("com.apple.reminders", .admin, false),
            ("com.1password.1password", .admin, false),
            ("com.raycast.macos", .admin, false),
            ("com.runningwithcrayons.Alfred", .admin, false),
            
            // --- Meta ---
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
            Task { @MainActor [weak self] in
                self?.handleDomainChange(from: oldDomain, to: newDomain, title: title)
            }
        }
        
        // --- System Lifecycle Observers ---
        
        // Sleep/Wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleSleep() }
            }
            .store(in: &cancellables)
            
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleWake() }
            }
            .store(in: &cancellables)
            
        // App Termination
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleTermination() }
            }
            .store(in: &cancellables)
    }
    
    private func startHeartbeat() {
        Task { @MainActor [weak self] in
            while true {
                // Heartbeat every 30 seconds
                try? await Task.sleep(for: .seconds(30))
                guard let self = self else { return }
                self.saveHeartbeat()
            }
        }
    }
    
    // MARK: - Lifecycle Handlers
    
    private func handleSleep() {
        print("TrackerService: System sleeping - pausing tracking")
        // Close current session to prevent duration accumulating during sleep
        closeCurrentSession()
    }
    
    private func handleWake() {
        print("TrackerService: System woke up - resuming tracking")
        // Trigger app change to pick up whatever is frontmost
        handleAppChange()
    }
    
    private func handleTermination() {
        print("TrackerService: App terminating - closing session")
        closeCurrentSession()
        do {
            try modelContext.save()
        } catch {
            print("TrackerService: Failed to save on termination: \(error)")
        }
    }
    
    private func saveHeartbeat() {
        guard let session = currentSession else { return }
        
        // Update accumulated duration without closing
        let activeStart = session.lastResumedAt ?? session.startTimestamp
        let currentSegment = Date().timeIntervalSince(activeStart)
        
        // We act as if we closed and resumed instantly to checkpoint the duration
        session.accumulatedDuration += currentSegment
        session.lastResumedAt = Date()
        
        do {
            try modelContext.save()
            // print("TrackerService: Heartbeat saved (\(Int(session.accumulatedDuration))s)")
        } catch {
            print("TrackerService: Heartbeat save failed: \(error)")
        }
    }
    
    // MARK: - Browser Domain Changes
    
    private var currentBrowserVisit: BrowserVisit?
    
    private func handleDomainChange(from oldDomain: String, to newDomain: String, title: String?) {
        // We received a domain change from the extension, so this IS a browser session
        guard let session = currentSession else { return }
        
        // Capture state BEFORE closing (which might delete the session if short)
        let bundleID = session.bundleID
        let appName = session.appName
        let state = session.state
        
        // Close the previous visit
        if let visit = currentBrowserVisit {
            visit.endTimestamp = Date()
        }
        
        // Get rich context for AI inference
        let richContext = browserBridge.getRichContext()
        
        // SPLIT: Close current session and create new one for the new domain
        // This enables per-domain AI classification
        closeCurrentSession()
        
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
            
            // CRITICAL FIX: Close the *current* session (the interruption) before resuming the old one.
            // If we don't, the current active session becomes a zombie (stays open forever but untracked).
            if currentSession != nil {
                closeCurrentSession() 
            }
            
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
            currentSession = nil // Clear reference first to notify UI
            modelContext.delete(session)
            print("TrackerService: Discarded short session \(session.appName) (\(String(format: "%.1f", session.duration))s)")
            return
        }
        
        // Add to recent sessions for merge detection (only non-Meta)
        if !session.isDeleted && session.activityType != .meta {
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

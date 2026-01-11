//
//  ClusterEngine.swift
//  Minute
//
//  Groups adjacent sessions into task clusters for end-of-day review
//

import Foundation
import SwiftData

/// Engine for grouping sessions into task clusters
class ClusterEngine {
    
    // MARK: - Configuration
    
    /// Maximum gap between sessions to still be in same cluster (seconds)
    let maxGapThreshold: TimeInterval = 5 * 60  // 5 minutes
    
    /// Short interruption threshold - quick checks don't break a cluster (seconds)
    let shortInterruptionThreshold: TimeInterval = 2 * 60  // 2 minutes
    
    /// Minimum cluster duration to be meaningful (seconds)
    let minClusterDuration: TimeInterval = 3 * 60  // 3 minutes
    
    // MARK: - Task Label Rules
    
    /// Domain patterns → task labels
    let domainTaskRules: [(pattern: String, label: String)] = [
        ("github.com", "Coding"),
        ("gitlab.com", "Coding"),
        ("stackoverflow.com", "Research"),
        ("developer.apple.com", "Research"),
        ("docs.google.com", "Documents"),
        ("sheets.google.com", "Spreadsheets"),
        ("slides.google.com", "Presentation"),
        ("figma.com", "Design"),
        ("canva.com", "Design"),
        ("dribbble.com", "Design Inspiration"),
        ("behance.net", "Design Inspiration"),
        ("notion.so", "Notes"),
        ("asana.com", "Project Management"),
        ("linear.app", "Project Management"),
        ("trello.com", "Project Management"),
        ("slack.com", "Communication"),
        ("discord.com", "Communication"),
        ("mail.google.com", "Email"),
        ("outlook.office.com", "Email"),
        ("outlook.live.com", "Email"),
        ("calendar.google.com", "Scheduling"),
        ("zoom.us", "Meetings"),
        ("meet.google.com", "Meetings"),
        ("teams.microsoft.com", "Meetings"),
        ("chatgpt.com", "AI Assistance"),
        ("claude.ai", "AI Assistance"),
        ("openai.com", "AI Research"),
    ]
    
    /// App patterns → task labels
    let appTaskRules: [(bundleID: String, label: String)] = [
        ("com.apple.dt.Xcode", "iOS Development"),
        ("com.microsoft.VSCode", "Coding"),
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "Terminal"),
        ("com.apple.mail", "Email"),
        ("com.apple.iCal", "Scheduling"),
        ("com.figma.Desktop", "Design"),
        ("com.adobe.Photoshop", "Design"),
        ("com.adobe.illustrator", "Design"),
        ("com.tinyspeck.slackmacgap", "Communication"),
        ("com.hnc.Discord", "Communication"),
        ("us.zoom.xos", "Meeting"),
        ("com.microsoft.teams", "Meeting"),
        ("readdle.spark.mac", "Email"),
    ]
    
    // MARK: - Clustering Algorithm
    
    /// Generate clusters from a list of sessions
    func clusterSessions(_ sessions: [Session]) -> [ClusterResult] {
        let sorted = sessions
            .filter { $0.state == .active }  // Only active sessions
            .sorted { $0.startTimestamp < $1.startTimestamp }
        
        guard !sorted.isEmpty else { return [] }
        
        var clusters: [ClusterResult] = []
        var currentCluster: [Session] = [sorted[0]]
        
        for i in 1..<sorted.count {
            let prevSession = sorted[i - 1]
            let currSession = sorted[i]
            
            let gap = currSession.startTimestamp.timeIntervalSince(
                prevSession.endTimestamp ?? prevSession.startTimestamp
            )
            
            // Check if sessions should be in the same cluster
            let shouldMerge = shouldMergeSessions(
                previous: prevSession,
                current: currSession,
                gap: gap
            )
            
            if shouldMerge {
                currentCluster.append(currSession)
            } else {
                // Finish current cluster and start new one
                if let cluster = finalizeCluster(currentCluster) {
                    clusters.append(cluster)
                }
                currentCluster = [currSession]
            }
        }
        
        // Finalize last cluster
        if let cluster = finalizeCluster(currentCluster) {
            clusters.append(cluster)
        }
        
        return clusters
    }
    
    private func shouldMergeSessions(previous: Session, current: Session, gap: TimeInterval) -> Bool {
        // Too long of a gap
        if gap > maxGapThreshold {
            return false
        }
        
        // FOCUS THREADS: Break on productive → distraction transition
        // This creates distinct "focus periods" that end when you get distracted
        let prevIsProductive = previous.activityType.isProductive && !DistractionRules.isDistraction(session: previous)
        let currIsDistraction = DistractionRules.isDistraction(session: current)
        
        if prevIsProductive && currIsDistraction {
            return false  // Break the cluster - you lost focus
        }
        
        // Short interruption (like checking messages) - tolerate if very quick
        // But only if we're going back to productive work
        if previous.duration < shortInterruptionThreshold && !currIsDistraction {
            return true
        }
        
        // If currently distracted, keep distractions together
        let prevIsDistraction = DistractionRules.isDistraction(session: previous)
        if prevIsDistraction && currIsDistraction {
            return true  // Group distractions together
        }
        
        // Same primary surface (app or domain)
        if areSameSurface(previous, current) {
            return true
        }
        
        // Small gap and related activities
        if gap < 60 && areRelatedActivities(previous, current) {
            return true
        }
        
        return gap < 30  // Very short gaps always merge
    }
    
    private func areSameSurface(_ a: Session, _ b: Session) -> Bool {
        // Same app
        if a.bundleID == b.bundleID {
            return true
        }
        
        // Same domain (for browser sessions)
        if let domainA = a.browserDomain, let domainB = b.browserDomain {
            return domainA == domainB
        }
        
        return false
    }
    
    private func areRelatedActivities(_ a: Session, _ b: Session) -> Bool {
        // Both are productive types
        if a.activityType.isProductive && b.activityType.isProductive {
            return true
        }
        
        // Both are communication
        if a.activityType == .communication && b.activityType == .communication {
            return true
        }
        
        return false
    }
    
    private func finalizeCluster(_ sessions: [Session]) -> ClusterResult? {
        guard !sessions.isEmpty else { return nil }
        
        let startTime = sessions.first!.startTimestamp
        let endTime = sessions.last!.endTimestamp ?? Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Skip very short clusters
        guard duration >= minClusterDuration else { return nil }
        
        // Determine primary app and domain
        let appCounts = Dictionary(grouping: sessions, by: { $0.bundleID })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        let primaryApp = appCounts.max(by: { $0.value < $1.value })?.key
        
        let domainCounts = Dictionary(grouping: sessions.compactMap { $0.browserDomain }, by: { $0 })
            .mapValues { $0.count }
        let primaryDomain = domainCounts.max(by: { $0.value < $1.value })?.key
        
        // Suggest a label
        let (label, confidence) = suggestLabel(
            primaryApp: primaryApp,
            primaryDomain: primaryDomain,
            sessions: sessions
        )
        
        return ClusterResult(
            startTime: startTime,
            endTime: endTime,
            sessions: sessions,
            suggestedLabel: label,
            confidence: confidence,
            primaryApp: sessions.first { $0.bundleID == primaryApp }?.appName,
            primaryDomain: primaryDomain
        )
    }
    
    private func suggestLabel(primaryApp: String?, primaryDomain: String?, sessions: [Session]) -> (String?, Double) {
        // Priority 1: User-set label
        for session in sessions {
            if let userLabel = session.userTaskLabel {
                return (userLabel, 1.0)
            }
        }
        
        // Priority 2: AI-inferred label (from Gemini)
        let aiLabels = sessions.compactMap { $0.inferredTask }
        if let mostCommonAI = aiLabels.mostCommon() {
            return (mostCommonAI, 0.95)
        }
        
        // Priority 3: Domain rules (more specific)
        if let domain = primaryDomain {
            for rule in domainTaskRules {
                if domain.contains(rule.pattern) {
                    return (rule.label, 0.9)
                }
            }
        }
        
        // Priority 4: App rules
        if let bundleID = primaryApp {
            for rule in appTaskRules {
                if bundleID == rule.bundleID {
                    return (rule.label, 0.85)
                }
            }
        }
        
        // Fall back to activity type
        let activityCounts = Dictionary(grouping: sessions, by: { $0.activityType })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        if let primaryActivity = activityCounts.max(by: { $0.value < $1.value })?.key {
            return (primaryActivity.rawValue, 0.5)
        }
        
        return (nil, 0)
    }
}

// MARK: - Array Extension for Most Common

extension Array where Element: Hashable {
    func mostCommon() -> Element? {
        let counts = Dictionary(grouping: self, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }
    
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Cluster Result (non-persisted)

/// Temporary cluster result before saving
struct ClusterResult: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let sessions: [Session]
    let suggestedLabel: String?
    let confidence: Double
    let primaryApp: String?
    let primaryDomain: String?
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var sessionCount: Int {
        sessions.count
    }
    
    var label: String {
        suggestedLabel ?? "Unlabeled"
    }
}

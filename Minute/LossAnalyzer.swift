//
//  LossAnalyzer.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import Foundation
import SwiftData

/// Represents a detected loss event with context
struct LossEvent: Identifiable {
    let id = UUID()
    let type: LossType
    let startTime: Date
    let endTime: Date
    let lossMinutes: Double
    let explanation: String
    let affectedSessions: [Session]
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

/// Daily loss summary with all metrics
struct DailyLossReport {
    let date: Date
    let totalLossMinutes: Double
    let lossEvents: [LossEvent]
    
    // Metrics
    let productiveMinutes: Double  // Only from isProductive sessions
    let activeMinutes: Double      // All active time (including neutral)
    let idleLossMinutes: Double
    let distractionLossMinutes: Double
    let switchingLossMinutes: Double
    let recoveryLossMinutes: Double
    let frictionLossMinutes: Double
    
    // Micro-distractions (NEW)
    let microDistractionCount: Int
    let microDistractionDuration: TimeInterval
    let microDistractionsByDomain: [String: Int]  // domain: count
    
    let deepBlockCount: Int
    let switchingRate: Double // switches per hour
    let fragmentationScore: Double // 0-1, higher = more fragmented
}

/// Analyzes sessions to detect loss patterns
class LossAnalyzer {
    
    // MARK: - Thresholds (Configurable)
    
    /// Minimum idle duration to count as loss (seconds)
    let idleLossThreshold: TimeInterval = 120 // 2 min
    
    /// Minimum duration to count as "deep work" (seconds)
    let deepBlockThreshold: TimeInterval = 20 * 60 // 20 min (more achievable)
    
    /// Switches per hour that trigger "switching storm" (40 = ~every 90 seconds)
    let switchingStormThreshold: Double = 40
    
    /// Duration below which we count as "fragmented" (seconds)
    let fragmentedBlockThreshold: TimeInterval = 3 * 60 // 3 min
    
    /// Window size for detecting switching storms (seconds)
    let switchingWindowSize: TimeInterval = 15 * 60 // 15 min window
    
    /// Grace period before distraction counts as loss (seconds)
    let distractionGracePeriod: TimeInterval = 120 // 2 min
    
    // MARK: - Analysis
    
    func analyzeDay(sessions: [Session], for date: Date = Date()) -> DailyLossReport {
        let calendar = Calendar.current
        let daySessions = sessions.filter { calendar.isDate($0.startTimestamp, inSameDayAs: date) }
            .sorted { $0.startTimestamp < $1.startTimestamp }
        
        // Detect loss events
        let idleLoss = detectIdleLoss(sessions: daySessions)
        let distractionLoss = detectDistractionLoss(sessions: daySessions)
        let switchingLoss = detectSwitchingStorms(sessions: daySessions)
        let recoveryLoss = detectRecoveryLoss(sessions: daySessions)
        let frictionLoss = detectFrictionLoss(sessions: daySessions)
        
        // Detect micro-distractions (under grace threshold)
        let microDistractions = detectMicroDistractions(sessions: daySessions)
        let microByDomain = Dictionary(grouping: microDistractions, by: { $0.domain ?? "Unknown" })
            .mapValues { $0.count }
        
        let allLoss = idleLoss + distractionLoss + switchingLoss + recoveryLoss + frictionLoss
        
        // Calculate metrics
        let productiveMinutes = daySessions
            .filter { $0.state == .active && $0.activityType.isProductive }
            .reduce(0.0) { $0 + $1.duration } / 60.0
        
        let activeMinutes = daySessions
            .filter { $0.state == .active }
            .reduce(0.0) { $0 + $1.duration } / 60.0
        
        let deepBlocks = daySessions.filter {
            $0.state == .active &&
            $0.activityType.isProductive &&
            $0.duration >= deepBlockThreshold
        }.count
        
        let switchingRate = calculateSwitchingRate(sessions: daySessions)
        let fragmentationScore = calculateFragmentationScore(sessions: daySessions)
        
        return DailyLossReport(
            date: date,
            totalLossMinutes: allLoss.reduce(0) { $0 + $1.lossMinutes },
            lossEvents: allLoss.sorted { $0.lossMinutes > $1.lossMinutes },
            productiveMinutes: productiveMinutes,
            activeMinutes: activeMinutes,
            idleLossMinutes: idleLoss.reduce(0) { $0 + $1.lossMinutes },
            distractionLossMinutes: distractionLoss.reduce(0) { $0 + $1.lossMinutes },
            switchingLossMinutes: switchingLoss.reduce(0) { $0 + $1.lossMinutes },
            recoveryLossMinutes: recoveryLoss.reduce(0) { $0 + $1.lossMinutes },
            frictionLossMinutes: frictionLoss.reduce(0) { $0 + $1.lossMinutes },
            microDistractionCount: microDistractions.count,
            microDistractionDuration: microDistractions.reduce(0) { $0 + $1.duration },
            microDistractionsByDomain: microByDomain,
            deepBlockCount: deepBlocks,
            switchingRate: switchingRate,
            fragmentationScore: fragmentationScore
        )
    }
    
    // MARK: - Micro-Distraction Detection
    
    struct MicroDistraction {
        let session: Session
        let domain: String?
        let duration: TimeInterval
    }
    
    /// Detect distraction sessions UNDER the grace threshold
    func detectMicroDistractions(sessions: [Session]) -> [MicroDistraction] {
        sessions
            .filter { $0.state == .active && DistractionRules.isDistraction(session: $0) && $0.duration < distractionGracePeriod }
            .map { session in
                MicroDistraction(
                    session: session,
                    domain: session.browserDomain,
                    duration: session.duration
                )
            }
    }
    
    // MARK: - Idle Loss Detection
    
    func detectIdleLoss(sessions: [Session]) -> [LossEvent] {
        sessions
            .filter { $0.state == .idle && $0.duration >= idleLossThreshold }
            .map { session in
                LossEvent(
                    type: .idle,
                    startTime: session.startTimestamp,
                    endTime: session.endTimestamp ?? Date(),
                    lossMinutes: session.duration / 60.0,
                    explanation: "Idle for \(formatDuration(session.duration))",
                    affectedSessions: [session]
                )
            }
    }
    
    // MARK: - Distraction Loss Detection
    
    func detectDistractionLoss(sessions: [Session]) -> [LossEvent] {
        sessions
            .filter { $0.state == .active && DistractionRules.isDistraction(session: $0) && $0.duration > distractionGracePeriod }
            .map { session in
                // Once over grace period, count the entire distraction
                let lossTime = session.duration
                let source = session.browserDomain ?? session.appName
                return LossEvent(
                    type: .distraction,
                    startTime: session.startTimestamp,
                    endTime: session.endTimestamp ?? Date(),
                    lossMinutes: lossTime / 60.0,
                    explanation: "\(source) for \(formatDuration(session.duration))",
                    affectedSessions: [session]
                )
            }
    }
    
    // MARK: - Switching Storm Detection
    
    func detectSwitchingStorms(sessions: [Session]) -> [LossEvent] {
        var lossEvents: [LossEvent] = []
        let activeSessions = sessions.filter { $0.state == .active }
        
        guard activeSessions.count > 1 else { return [] }
        
        // Sliding window analysis
        var windowStart = 0
        
        while windowStart < activeSessions.count {
            let windowStartTime = activeSessions[windowStart].startTimestamp
            let windowEndTime = windowStartTime.addingTimeInterval(switchingWindowSize)
            
            let windowSessions = activeSessions.filter {
                $0.startTimestamp >= windowStartTime && $0.startTimestamp < windowEndTime
            }
            
            let switchCount = windowSessions.count - 1
            let durationHours = switchingWindowSize / 3600.0
            let rate = Double(switchCount) / durationHours
            
            if rate >= switchingStormThreshold {
                // Find actual end time
                let actualEnd = windowSessions.last?.endTimestamp ?? windowEndTime
                let stormDuration = actualEnd.timeIntervalSince(windowStartTime)
                
                lossEvents.append(LossEvent(
                    type: .switching,
                    startTime: windowStartTime,
                    endTime: actualEnd,
                    lossMinutes: stormDuration * 0.2 / 60.0, // 20% of storm time is "lost"
                    explanation: "\(switchCount) switches in \(formatDuration(stormDuration)) (\(Int(rate))/hr)",
                    affectedSessions: windowSessions
                ))
                
                // Skip past this storm
                windowStart += windowSessions.count
            } else {
                windowStart += 1
            }
        }
        
        return lossEvents
    }
    
    // MARK: - Recovery Loss Detection
    
    func detectRecoveryLoss(sessions: [Session]) -> [LossEvent] {
        var lossEvents: [LossEvent] = []
        
        for (index, session) in sessions.enumerated() {
            // Look for distraction -> work transitions
            guard session.activityType.isDistraction,
                  index + 1 < sessions.count else { continue }
            
            // Find next productive session
            var recoveryTime: TimeInterval = 0
            var recoverySessions: [Session] = []
            
            for nextIndex in (index + 1)..<sessions.count {
                let next = sessions[nextIndex]
                
                if next.activityType.isProductive {
                    break // Found work, recovery complete
                }
                
                recoveryTime += next.duration
                recoverySessions.append(next)
                
                if recoveryTime > 10 * 60 { // Cap at 10 min
                    break
                }
            }
            
            // If recovery took > 2 min, count excess as loss
            if recoveryTime > 2 * 60 {
                let lossTime = recoveryTime - 2 * 60
                lossEvents.append(LossEvent(
                    type: .recovery,
                    startTime: session.endTimestamp ?? session.startTimestamp,
                    endTime: recoverySessions.last?.endTimestamp ?? Date(),
                    lossMinutes: lossTime / 60.0,
                    explanation: "Slow return to work after \(session.appName)",
                    affectedSessions: [session] + recoverySessions
                ))
            }
        }
        
        return lossEvents
    }
    
    // MARK: - Friction/Fragmentation Loss
    
    func detectFrictionLoss(sessions: [Session]) -> [LossEvent] {
        let productiveSessions = sessions.filter {
            $0.state == .active && $0.activityType.isProductive
        }
        
        // Count blocks that are too short
        let fragmentedBlocks = productiveSessions.filter {
            $0.duration < fragmentedBlockThreshold && $0.duration >= 30 // At least 30s
        }
        
        guard fragmentedBlocks.count >= 3 else { return [] }
        
        // Estimate friction loss as 20% of fragmented time
        let fragmentedTime = fragmentedBlocks.reduce(0.0) { $0 + $1.duration }
        let lossTime = fragmentedTime * 0.2
        
        guard let first = fragmentedBlocks.first,
              let last = fragmentedBlocks.last else { return [] }
        
        return [LossEvent(
            type: .friction,
            startTime: first.startTimestamp,
            endTime: last.endTimestamp ?? Date(),
            lossMinutes: lossTime / 60.0,
            explanation: "\(fragmentedBlocks.count) blocks under \(Int(fragmentedBlockThreshold/60)) min",
            affectedSessions: fragmentedBlocks
        )]
    }
    
    // MARK: - Metrics
    
    func calculateSwitchingRate(sessions: [Session]) -> Double {
        let activeSessions = sessions.filter { $0.state == .active }
        guard activeSessions.count > 1 else { return 0 }
        
        let totalDuration = activeSessions.reduce(0.0) { $0 + $1.duration }
        let hours = totalDuration / 3600.0
        
        guard hours > 0 else { return 0 }
        return Double(activeSessions.count - 1) / hours
    }
    
    func calculateFragmentationScore(sessions: [Session]) -> Double {
        let productiveSessions = sessions.filter {
            $0.state == .active && $0.activityType.isProductive
        }
        
        guard !productiveSessions.isEmpty else { return 0 }
        
        let fragmentedTime = productiveSessions
            .filter { $0.duration < fragmentedBlockThreshold }
            .reduce(0.0) { $0 + $1.duration }
        
        let totalTime = productiveSessions.reduce(0.0) { $0 + $1.duration }
        
        return totalTime > 0 ? fragmentedTime / totalTime : 0
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

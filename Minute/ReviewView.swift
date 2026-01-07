//
//  ReviewView.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import SwiftUI
import SwiftData

struct ReviewView: View {
    @EnvironmentObject var tracker: TrackerService
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Session.startTimestamp, order: .forward) private var sessions: [Session]
    @State private var selectedSession: Session?
    @State private var showingMapSheet = false
    @State private var sessionToMap: Session?
    @State private var lossReport: DailyLossReport?
    
    private let lossAnalyzer = LossAnalyzer()
    
    var body: some View {
        HStack(spacing: 0) {
            // Full-height timeline sidebar
            TimelineSidebar(sessions: todaySessions, selectedSession: $selectedSession)
                .padding(.vertical, 8)
                .padding(.leading, 8)
            
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    header
                    metricsRow
                    lossBreakdownBar
                    lossExplanationsSection
                    sessionListSection
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { updateLossReport() }
        .onChange(of: sessions.count) { _, _ in updateLossReport() }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .frame(minWidth: 450, minHeight: 350)
        }
        .sheet(isPresented: $showingMapSheet) {
            if let session = sessionToMap {
                MapAppSheet(session: session, tracker: tracker) {
                    showingMapSheet = false
                }
                .frame(minWidth: 350, minHeight: 250)
            }
        }
    }
    
    private func updateLossReport() {
        lossReport = lossAnalyzer.analyzeDay(sessions: todaySessions)
    }
    
    // MARK: - Header
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.largeTitle.bold())
                Text(Date().formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            if let current = tracker.currentSession {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(current.appName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
    
    // MARK: - Metrics Row
    var metricsRow: some View {
        HStack(spacing: 12) {
            // Productive Time
            MetricCard(
                title: "Productive",
                value: formatMinutes(lossReport?.productiveMinutes ?? 0),
                icon: "checkmark.circle.fill",
                color: .green,
                isPrimary: false
            )
            
            // Loss Minutes (PRIMARY)
            MetricCard(
                title: "Lost",
                value: formatMinutes(lossReport?.totalLossMinutes ?? 0),
                icon: "clock.badge.exclamationmark.fill",
                color: .red,
                isPrimary: true
            )
            
            // Micro-Distractions (NEW)
            MetricCard(
                title: "Micro-checks",
                value: "\(lossReport?.microDistractionCount ?? 0)",
                icon: "bolt.fill",
                color: .orange,
                isPrimary: false
            )
            
            // Switching Rate
            MetricCard(
                title: "Switches/hr",
                value: "\(Int(lossReport?.switchingRate ?? 0))",
                icon: "arrow.left.arrow.right",
                color: switchingRateColor,
                isPrimary: false
            )
        }
    }
    
    var switchingRateColor: Color {
        guard let rate = lossReport?.switchingRate else { return .gray }
        if rate > 40 { return .red }      // Storm threshold
        if rate > 25 { return .orange }   // Warning
        return .green
    }
    
    // MARK: - Loss Breakdown Bar
    var lossBreakdownBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Loss Breakdown")
                    .font(.headline)
                Spacer()
                
                HStack(spacing: 12) {
                    LossLegendItem(type: .idle, color: .orange)
                    LossLegendItem(type: .distraction, color: .red)
                    LossLegendItem(type: .switching, color: .purple)
                }
                .font(.caption)
            }
            
            LossBreakdownCanvas(report: lossReport)
                .frame(height: 24)
        }
    }
    
    // MARK: - Loss Explanations
    var lossExplanationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Loss Breakdown")
                    .font(.headline)
                Spacer()
                if let total = lossReport?.totalLossMinutes, total > 0 {
                    Text("\(Int(total))m total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Micro-distractions summary (NEW)
            if let report = lossReport, report.microDistractionCount > 0 {
                microDistractionsSummary(report: report)
            }
            
            // Loss event explanations
            if let events = lossReport?.lossEvents, !events.isEmpty {
                ForEach(generateExplanations(events: events, report: lossReport).prefix(5)) { explanation in
                    LossExplanationRow(explanation: explanation)
                }
                
                if events.count > 5 {
                    Text("+ \(events.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if lossReport?.microDistractionCount ?? 0 == 0 {
                Text("No significant loss events detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func microDistractionsSummary(report: DailyLossReport) -> some View {
        let topDomain = report.microDistractionsByDomain.max(by: { $0.value < $1.value })
        let durationSeconds = Int(report.microDistractionDuration)
        let durationStr = durationSeconds >= 60 ? "\(durationSeconds / 60)m \(durationSeconds % 60)s" : "\(durationSeconds)s"
        
        return HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.microDistractionCount) micro-checks")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                
                HStack(spacing: 4) {
                    Text(durationStr + " total")
                    if let domain = topDomain {
                        Text("•")
                        Text("mostly \(domain.key)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    struct LossExplanation: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let summary: String
        let detail: String
    }
    
    func generateExplanations(events: [LossEvent], report: DailyLossReport?) -> [LossExplanation] {
        var explanations: [LossExplanation] = []
        
        // Group by type
        let byType = Dictionary(grouping: events, by: { $0.type })
        
        // Distraction summary
        if let distractionEvents = byType[.distraction], !distractionEvents.isEmpty {
            let totalMins = distractionEvents.reduce(0.0) { $0 + $1.lossMinutes }
            let apps = Set(distractionEvents.compactMap { $0.affectedSessions.first?.browserDomain ?? $0.affectedSessions.first?.appName })
            let appList = apps.prefix(3).joined(separator: ", ")
            explanations.append(LossExplanation(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                summary: "\(Int(totalMins))m on distractions",
                detail: appList
            ))
        }
        
        // Idle summary
        if let idleEvents = byType[.idle], !idleEvents.isEmpty {
            let totalMins = idleEvents.reduce(0.0) { $0 + $1.lossMinutes }
            explanations.append(LossExplanation(
                icon: "moon.fill",
                color: .orange,
                summary: "\(Int(totalMins))m idle time",
                detail: "\(idleEvents.count) idle periods over 2 min"
            ))
        }
        
        // Switching storm summary
        if let switchingEvents = byType[.switching], !switchingEvents.isEmpty {
            let totalMins = switchingEvents.reduce(0.0) { $0 + $1.lossMinutes }
            if let rate = report?.switchingRate, rate > 25 {
                explanations.append(LossExplanation(
                    icon: "arrow.left.arrow.right",
                    color: .purple,
                    summary: "High switching rate",
                    detail: "\(Int(rate)) switches/hr → \(Int(totalMins))m fragmentation"
                ))
            }
        }
        
        // Recovery summary
        if let recoveryEvents = byType[.recovery], !recoveryEvents.isEmpty {
            let totalMins = recoveryEvents.reduce(0.0) { $0 + $1.lossMinutes }
            explanations.append(LossExplanation(
                icon: "arrow.clockwise",
                color: .blue,
                summary: "\(Int(totalMins))m recovery time",
                detail: "Time to refocus after \(recoveryEvents.count) distraction dives"
            ))
        }
        
        return explanations.sorted { $0.summary > $1.summary }
    }
    
    // MARK: - Session List Section (timeline is in sidebar)
    var sessionListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.title2.bold())
                Spacer()
                Text("\(todaySessions.count) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if todaySessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "clock",
                    description: Text("Switch between apps to start tracking")
                )
                .frame(height: 150)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(todaySessions.suffix(15).reversed()) { session in
                        SessionRow(session: session) {
                            selectedSession = session
                        } onMapApp: {
                            sessionToMap = session
                            showingMapSheet = true
                        }
                    }
                }
                
                if todaySessions.count > 15 {
                    Text("Showing 15 most recent • \(todaySessions.count - 15) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
    
    // MARK: - Helpers
    var todaySessions: [Session] {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDateInToday($0.startTimestamp) }
    }
    
    /// Consolidated sessions - groups consecutive browser sessions by app
    var consolidatedTodaySessions: [ConsolidatedSession] {
        var result: [ConsolidatedSession] = []
        var currentGroup: [Session] = []
        var currentBundleID: String?
        
        for session in todaySessions {
            if session.activityType == .browser,
               let bundleID = currentBundleID,
               session.bundleID == bundleID {
                // Same browser, add to current group
                currentGroup.append(session)
            } else {
                // Different app or not browser - flush current group
                if !currentGroup.isEmpty {
                    result.append(ConsolidatedSession(sessions: currentGroup))
                    currentGroup = []
                }
                
                if session.activityType == .browser {
                    // Start new browser group
                    currentGroup = [session]
                    currentBundleID = session.bundleID
                } else {
                    // Non-browser - add as single session
                    result.append(ConsolidatedSession(sessions: [session]))
                    currentBundleID = nil
                }
            }
        }
        
        // Flush remaining group
        if !currentGroup.isEmpty {
            result.append(ConsolidatedSession(sessions: currentGroup))
        }
        
        return result
    }
    
    func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = Int(minutes) / 60
            let mins = Int(minutes) % 60
            return "\(hours)h \(mins)m"
        }
        return "\(Int(minutes))m"
    }
}

// MARK: - Consolidated Session (for UI grouping)
struct ConsolidatedSession: Identifiable {
    let id = UUID()
    let sessions: [Session]
    
    var primarySession: Session { sessions.first! }
    var isBrowserGroup: Bool { sessions.count > 1 }
    var appName: String { primarySession.appName }
    var bundleID: String { primarySession.bundleID }
    var activityType: ActivityType { primarySession.activityType }
    var startTimestamp: Date { sessions.first?.startTimestamp ?? Date() }
    var endTimestamp: Date? { sessions.last?.endTimestamp }
    
    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }
    
    var domains: [String] {
        sessions.compactMap { $0.browserDomain }.unique()
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isPrimary: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, options: .repeating, isActive: isPrimary)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            
            Text(value)
                .font(isPrimary ? .title.bold() : .title2.bold())
                .foregroundStyle(isPrimary ? color : .primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            ZStack {
                // Base glass material
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                
                // Gradient overlay for depth
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.1), .clear, .black.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Accent tint for primary cards
                if isPrimary {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.1))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: isPrimary 
                            ? [color.opacity(0.4), color.opacity(0.15)]
                            : [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: isPrimary ? color.opacity(0.15) : .black.opacity(0.06), radius: isHovered ? 10 : 4, x: 0, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Loss Legend Item
struct LossLegendItem: View {
    let type: LossType
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(type.rawValue)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Loss Breakdown Canvas
struct LossBreakdownCanvas: View {
    let report: DailyLossReport?
    
    var body: some View {
        Canvas { context, size in
            guard let report = report, report.totalLossMinutes > 0 else {
                // Empty state
                let rect = CGRect(origin: .zero, size: size)
                context.fill(RoundedRectangle(cornerRadius: 6).path(in: rect), with: .color(.gray.opacity(0.2)))
                return
            }
            
            var x: CGFloat = 0
            let total = report.totalLossMinutes
            
            // Draw each loss type
            let segments: [(Double, Color)] = [
                (report.idleLossMinutes, .orange),
                (report.distractionLossMinutes, .red),
                (report.switchingLossMinutes, .purple),
                (report.recoveryLossMinutes, .pink),
                (report.frictionLossMinutes, .gray)
            ]
            
            for (value, color) in segments where value > 0 {
                let width = CGFloat(value / total) * size.width
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                let path = RoundedRectangle(cornerRadius: 4).path(in: rect.insetBy(dx: 0.5, dy: 0))
                context.fill(path, with: .color(color))
                x += width
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Loss Event Row
struct LossEventRow: View {
    let event: LossEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Circle()
                .fill(colorForType.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: iconForType)
                        .font(.caption)
                        .foregroundStyle(colorForType)
                )
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(formatLossTime(event.lossMinutes))
                    .font(.subheadline.bold())
                Text(event.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Time
            Text(event.startTime, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    var colorForType: Color {
        switch event.type {
        case .idle: return .orange
        case .distraction: return .red
        case .switching: return .purple
        case .recovery: return .pink
        case .friction: return .gray
        }
    }
    
    var iconForType: String {
        switch event.type {
        case .idle: return "moon.fill"
        case .distraction: return "exclamationmark.triangle.fill"
        case .switching: return "arrow.left.arrow.right"
        case .recovery: return "arrow.clockwise"
        case .friction: return "square.split.2x2"
        }
    }
    
    func formatLossTime(_ minutes: Double) -> String {
        if minutes >= 1 {
            return "\(Int(minutes))m lost"
        } else {
            let seconds = Int(minutes * 60)
            return "\(seconds)s lost"
        }
    }
}

// MARK: - Loss Explanation Row (Grouped summary)
struct LossExplanationRow: View {
    let explanation: ReviewView.LossExplanation
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Circle()
                .fill(explanation.color.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: explanation.icon)
                        .font(.caption)
                        .foregroundStyle(explanation.color)
                )
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(explanation.summary)
                    .font(.subheadline.bold())
                Text(explanation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Timeline With Loss Markers
struct TimelineWithLoss: View {
    let sessions: [Session]
    let lossEvents: [LossEvent]
    
    var body: some View {
        Canvas { context, size in
            let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
            guard totalDuration > 0 else { return }
            
            var x: CGFloat = 0
            
            for session in sessions {
                let width = CGFloat(session.duration / totalDuration) * size.width
                let rect = CGRect(x: x, y: 0, width: max(width, 2), height: size.height)
                
                // Base color by activity type
                let baseColor = colorForSession(session)
                let path = RoundedRectangle(cornerRadius: 3).path(in: rect.insetBy(dx: 0.5, dy: 0))
                context.fill(path, with: .color(baseColor))
                
                // Add subtle hatching if this session is in a loss event
                if isLossSession(session) && rect.width > 8 {
                    // Draw subtle diagonal stripes for loss - wider spacing, lower opacity
                    for i in stride(from: 0, to: rect.width + rect.height, by: 12) {
                        var stripePath = Path()
                        stripePath.move(to: CGPoint(x: rect.minX + i, y: rect.minY))
                        stripePath.addLine(to: CGPoint(x: rect.minX + i - rect.height, y: rect.maxY))
                        context.stroke(stripePath, with: .color(.white.opacity(0.4)), lineWidth: 2)
                    }
                }
                
                x += max(width, 2) + 1
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    func isLossSession(_ session: Session) -> Bool {
        lossEvents.contains { event in
            event.affectedSessions.contains { $0.id == session.id }
        }
    }
    
    func colorForSession(_ session: Session) -> Color {
        if session.state == .idle || session.state == .away {
            return .gray.opacity(0.4)
        }
        if session.activityType.isDistraction {
            return .red.opacity(0.6)
        }
        if session.activityType.isProductive {
            return .green
        }
        return session.needsReview ? .orange : .blue
    }
}

// MARK: - Session Row (existing, simplified reference)
struct SessionRow: View {
    let session: Session
    let onTap: () -> Void
    let onMapApp: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            mainRow
            
            // Show browser visits for browser sessions
            if session.activityType == .browser && (!session.browserVisits.isEmpty || session.browserDomain != nil) {
                browserVisitsSection
            }
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundForSession)
                
                // Subtle gradient for glass effect
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    LinearGradient(
                        colors: isHovered 
                            ? [.white.opacity(0.25), .white.opacity(0.1)]
                            : [borderColor, borderColor.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.04), radius: isHovered ? 8 : 2, x: 0, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
    }
    
    var mainRow: some View {
        HStack(spacing: 12) {
            // App Icon
            AppIconView(bundleID: session.bundleID, size: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTimestamp, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Text(formatDuration(session.duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 60, alignment: .leading)
            
            // Activity Color Bar
            RoundedRectangle(cornerRadius: 2)
                .fill(colorForActivityType(session.activityType))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.appName)
                        .font(.headline)
                    
                    // Show primary browser domain if available
                    if let domain = session.browserDomain {
                        let isDistraction = DistractionRules.isDistraction(domain: domain)
                        Text(domain)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isDistraction ? .red.opacity(0.15) : .gray.opacity(0.1))
                            .foregroundStyle(isDistraction ? .red : .secondary)
                            .clipShape(Capsule())
                    }
                    
                    if session.microInterruptions > 0 {
                        Text("×\(session.microInterruptions + 1)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    
                    // Show visit count badge
                    if session.browserVisits.count > 1 {
                        Text("\(session.browserVisits.count) sites")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 8) {
                    ActivityBadge(type: session.activityType, needsReview: session.needsReview)
                    
                    if let reason = session.unknownReason {
                        Text(reason.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if session.needsReview && session.unknownReason != .idle {
                Button("Map App…") {
                    onMapApp()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Button {
                onTap()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    var browserVisitsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            VStack(spacing: 4) {
                if !session.browserVisits.isEmpty {
                    ForEach(session.browserVisits.sorted { $0.startTimestamp < $1.startTimestamp }, id: \.id) { visit in
                        visitRow(domain: visit.domain, duration: visit.duration, isDistraction: visit.isDistraction)
                    }
                } else if let domain = session.browserDomain {
                    // Fallback to session domain
                    visitRow(domain: domain, duration: session.duration, isDistraction: DistractionRules.isDistraction(domain: domain))
                }
            }
            .padding(.vertical, 6)
        }
        .background(.background.opacity(0.5))
    }
    
    func visitRow(domain: String, duration: TimeInterval, isDistraction: Bool) -> some View {
        HStack(spacing: 8) {
            // Favicon from Google's service
            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Circle()
                    .fill(isDistraction ? .red.opacity(0.6) : .gray.opacity(0.4))
            }
            .frame(width: 14, height: 14)
            
            Text(domain)
                .font(.caption)
                .foregroundStyle(isDistraction ? .red : .secondary)
            
            Spacer()
            
            Text(formatDuration(duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 2)
    }
    
    var confidenceColor: Color {
        if session.state == .idle || session.state == .away {
            return .gray.opacity(0.5)
        }
        return session.needsReview ? .orange : .green
    }
    
    var backgroundForSession: some ShapeStyle {
        if session.needsReview && session.state == .active {
            return AnyShapeStyle(.orange.opacity(0.05))
        }
        return AnyShapeStyle(.background)
    }
    
    var borderColor: Color {
        if session.needsReview && session.state == .active {
            return .orange.opacity(0.3)
        }
        return .gray.opacity(0.2)
    }
    
    func colorForActivityType(_ type: ActivityType) -> Color {
        switch type {
        case .focusedWork: return .blue
        case .communication: return .purple
        case .browser: return .cyan
        case .entertainment: return .pink
        case .admin: return .mint
        case .referenceLearning: return .indigo
        case .idle: return .orange
        case .away: return .red
        case .unknown: return .gray
        case .meta: return .gray.opacity(0.5)
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Consolidated Session Row
struct ConsolidatedSessionRow: View {
    let consolidated: ConsolidatedSession
    let onTap: () -> Void
    let onMapApp: () -> Void
    
    @State private var isHovered = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            mainRow
            
            // Show domains if browser group is expanded
            if consolidated.isBrowserGroup && isExpanded {
                domainsSection
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.gray.opacity(isHovered ? 0.3 : 0.2), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if consolidated.isBrowserGroup {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } else {
                onTap()
            }
        }
    }
    
    var mainRow: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(consolidated.isBrowserGroup ? .cyan : colorForActivityType(consolidated.activityType))
                .frame(width: 10, height: 10)
            
            // Time
            VStack(alignment: .trailing) {
                Text(consolidated.startTimestamp, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                Text(formatDuration(consolidated.totalDuration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
            
            // App name & domains
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(consolidated.appName)
                        .font(.body)
                    
                    if consolidated.isBrowserGroup {
                        Text("(\(consolidated.sessions.count) sites)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Show domains preview
                if !consolidated.domains.isEmpty {
                    Text(consolidated.domains.prefix(3).joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Expand indicator for browser groups
            if consolidated.isBrowserGroup {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    var domainsSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 12)
            
            VStack(spacing: 4) {
                ForEach(consolidated.sessions, id: \.id) { session in
                    if let domain = session.browserDomain {
                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32")) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Circle().fill(.gray.opacity(0.4))
                            }
                            .frame(width: 14, height: 14)
                            
                            Text(domain)
                                .font(.caption)
                                .foregroundStyle(session.isGroupDistraction ? .orange : .primary)
                            
                            if let label = session.focusGroup?.name {
                                Text("• \(label)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            
                            Spacer()
                            
                            Text(formatDuration(session.duration))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .background(.background.opacity(0.5))
    }
    
    func colorForActivityType(_ type: ActivityType) -> Color {
        switch type {
        case .focusedWork: return .blue
        case .communication: return .purple
        case .browser: return .cyan
        case .entertainment: return .pink
        case .admin: return .mint
        case .referenceLearning: return .indigo
        case .idle: return .orange
        case .away: return .red
        case .unknown: return .gray
        case .meta: return .gray.opacity(0.5)
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Activity Badge
struct ActivityBadge: View {
    let type: ActivityType
    let needsReview: Bool
    
    var body: some View {
        Text(type.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    var color: Color {
        if needsReview { return .orange }
        switch type {
        case .focusedWork: return .blue
        case .communication: return .purple
        case .browser: return .cyan
        case .entertainment: return .pink
        case .admin: return .mint
        case .referenceLearning: return .indigo
        case .idle: return .orange
        case .away: return .red
        case .unknown: return .gray
        case .meta: return .gray
        }
    }
}

// MARK: - Map App Sheet
struct MapAppSheet: View {
    let session: Session
    let tracker: TrackerService
    let onDismiss: () -> Void
    
    @State private var selectedType: ActivityType = .focusedWork
    @State private var isAmbiguous = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Map \(session.appName)")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Bundle ID: \(session.bundleID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Activity Type", selection: $selectedType) {
                    ForEach(ActivityType.allCases.filter { $0 != .idle && $0 != .away && $0 != .unknown }, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("Mark as ambiguous (queue for review)", isOn: $isAmbiguous)
                
                Text("This will apply to all past and future occurrences of **\(session.appName)**.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Apply") {
                    tracker.mapApp(bundleID: session.bundleID, to: selectedType, isAmbiguous: isAmbiguous)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Session Detail View
struct SessionDetailView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.appName)
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Details section
                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Bundle ID", session.bundleID)
                            detailRow("Started", session.startTimestamp.formatted(date: .abbreviated, time: .standard))
                            detailRow("Duration", formatDuration(session.duration))
                            detailRow("State", session.state.rawValue.capitalized)
                            
                            if session.microInterruptions > 0 {
                                detailRow("Merged", "\(session.microInterruptions) micro-interruptions")
                            }
                        }
                    }
                    
                    // Classification section
                    GroupBox("Classification") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Activity Type", session.activityType.rawValue)
                            
                            HStack {
                                Text("Confidence")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(session.confidence * 100))%")
                                    .foregroundStyle(session.confidence >= 0.8 ? .green : .orange)
                            }
                            
                            if let reason = session.unknownReason {
                                detailRow("Reason", reason.rawValue)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}

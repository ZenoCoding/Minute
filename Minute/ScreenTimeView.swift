//
//  ScreenTimeView.swift
//  Minute
//
//  Created by Tycho Young on 1/2/26.
//

import SwiftUI
import SwiftData

struct ScreenTimeView: View {
    @Query(sort: \Session.startTimestamp, order: .forward) private var sessions: [Session]
    
    /// When true, browser domains appear as separate entries in Most Used
    @State private var showDomainsAsApps: Bool = false
    
    /// Debug mode to show session timeline
    @State private var showDebugTimeline: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                totalTimeCard
                usageChart
                
                if showDebugTimeline {
                    debugTimelineSection
                }
                
                appList
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Header
    var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Text("Screen Time")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    showDebugTimeline.toggle()
                } label: {
                    Image(systemName: showDebugTimeline ? "chart.bar.xaxis" : "chart.bar.xaxis")
                        .foregroundStyle(showDebugTimeline ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show debug timeline")
            }
            Text(Date().formatted(date: .complete, time: .omitted))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Total Time Card
    var totalTimeCard: some View {
        VStack(spacing: 8) {
            Text(formatDuration(totalActiveTime))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            
            Text("Total Screen Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Category breakdown
            HStack(spacing: 20) {
                CategoryPill(name: "Productive", duration: productiveTime, color: .green)
                CategoryPill(name: "Social", duration: socialTime, color: .blue)
                CategoryPill(name: "Entertainment", duration: entertainmentTime, color: .pink)
                CategoryPill(name: "Other", duration: otherTime, color: .gray)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Usage Chart (Bar Chart)
    var usageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Activity")
                .font(.headline)
            
            // Hourly breakdown bar chart
            HourlyBarChart(sessions: todaySessions)
                .frame(height: 120)
        }
        .padding()
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - App List
    var appList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Most Used")
                    .font(.headline)
                Spacer()
                Toggle("Domains as apps", isOn: $showDomainsAsApps)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            if showDomainsAsApps {
                domainListView
            } else {
                appListView
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }
    
    var appListView: some View {
        let appUsage = computeAppUsage()
        let maxDuration = appUsage.first?.duration ?? 1
        
        return ForEach(appUsage.prefix(10), id: \.bundleID) { app in
            AppUsageRow(
                appName: app.appName,
                bundleID: app.bundleID,
                duration: app.duration,
                activityType: app.activityType,
                maxDuration: maxDuration,
                domainBreakdown: app.domainBreakdown
            )
        }
    }
    
    var domainListView: some View {
        let domainUsage = computeDomainUsage()
        let maxDuration = domainUsage.first?.duration ?? 1
        
        return ForEach(domainUsage.prefix(15)) { domain in
            DomainAsAppRow(
                domain: domain.domain,
                duration: domain.duration,
                isDistraction: domain.isDistraction,
                maxDuration: maxDuration
            )
        }
    }
    
    // MARK: - Data Helpers
    
    /// System/background apps to exclude from screen time
    private let excludedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
    ]
    
    var todaySessions: [Session] {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDateInToday($0.startTimestamp) }
    }
    
    /// Sessions that count for screen time (excludes Meta/system)
    var screenTimeSessions: [Session] {
        todaySessions.filter { session in
            session.activityType != .meta &&
            !excludedBundleIDs.contains(session.bundleID)
        }
    }
    
    var totalActiveTime: TimeInterval {
        screenTimeSessions
            .filter { $0.state == .active }
            .reduce(0) { $0 + $1.duration }
    }
    
    var productiveTime: TimeInterval {
        screenTimeSessions
            .filter { $0.state == .active && $0.activityType.isProductive }
            .reduce(0) { $0 + $1.duration }
    }
    
    var socialTime: TimeInterval {
        screenTimeSessions
            .filter { $0.state == .active && $0.activityType == .communication }
            .reduce(0) { $0 + $1.duration }
    }
    
    var entertainmentTime: TimeInterval {
        screenTimeSessions
            .filter { $0.state == .active && DistractionRules.isDistraction(session: $0) }
            .reduce(0) { $0 + $1.duration }
    }
    
    var otherTime: TimeInterval {
        totalActiveTime - productiveTime - socialTime - entertainmentTime
    }
    
    struct AppUsageData {
        let bundleID: String
        let appName: String
        let duration: TimeInterval
        let activityType: ActivityType
        let domainBreakdown: [DomainUsageData]  // For browser apps
    }
    
    struct DomainUsageData: Identifiable {
        let id = UUID()
        let domain: String
        let duration: TimeInterval
        let isDistraction: Bool
    }
    
    func computeAppUsage() -> [AppUsageData] {
        var usage: [String: (appName: String, duration: TimeInterval, activityType: ActivityType)] = [:]
        var domainUsage: [String: [String: TimeInterval]] = [:]  // bundleID -> (domain -> duration)
        
        for session in screenTimeSessions where session.state == .active {
            let existing = usage[session.bundleID]
            usage[session.bundleID] = (
                appName: session.appName,
                duration: (existing?.duration ?? 0) + session.duration,
                activityType: session.activityType
            )
            
            // Collect domain usage for browser sessions
            if session.activityType == .browser {
                var bundleDomains = domainUsage[session.bundleID] ?? [:]
                
                // If we have specific visits, use them
                if !session.browserVisits.isEmpty {
                    for visit in session.browserVisits {
                        bundleDomains[visit.domain] = (bundleDomains[visit.domain] ?? 0) + visit.duration
                    }
                } 
                // Fallback: If no visits (or just 1-to-1 mapping), use the session's domain
                else if let domain = session.browserDomain {
                    bundleDomains[domain] = (bundleDomains[domain] ?? 0) + session.duration
                }
                
                domainUsage[session.bundleID] = bundleDomains
            }
        }
        
        return usage.map { bundleID, value in
            let domains = (domainUsage[bundleID] ?? [:]).map { domain, duration in
                DomainUsageData(
                    domain: domain,
                    duration: duration,
                    isDistraction: DistractionRules.isDistraction(domain: domain)
                )
            }.sorted { $0.duration > $1.duration }
            
            return AppUsageData(
                bundleID: bundleID,
                appName: value.appName,
                duration: value.duration,
                activityType: value.activityType,
                domainBreakdown: domains
            )
        }
        .sorted { $0.duration > $1.duration }
    }
    
    /// Compute all domains as separate entries (for domain-as-app mode)
    func computeDomainUsage() -> [DomainUsageData] {
        var domainDurations: [String: TimeInterval] = [:]
        
        for session in screenTimeSessions where session.state == .active {
            // For browser sessions, use full domain breakdown
            if session.activityType == .browser {
                if !session.browserVisits.isEmpty {
                    for visit in session.browserVisits {
                        domainDurations[visit.domain] = (domainDurations[visit.domain] ?? 0) + visit.duration
                    }
                } else if let domain = session.browserDomain {
                    domainDurations[domain] = (domainDurations[domain] ?? 0) + session.duration
                }
            } else {
                // For non-browser, use app name as "domain"
                domainDurations[session.appName] = (domainDurations[session.appName] ?? 0) + session.duration
            }
        }
        
        return domainDurations.map { domain, duration in
            DomainUsageData(
                domain: domain,
                duration: duration,
                isDistraction: DistractionRules.isDistraction(domain: domain)
            )
        }
        .sorted { $0.duration > $1.duration }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    // MARK: - Debug Timeline
    
    var debugTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Debug Timeline")
                    .font(.headline)
                Spacer()
                Text("\(todaySessions.count) sessions, \(screenTimeSessions.count) counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal) {
                debugTimelineView
                    .frame(height: 200)
            }
            
            // Session list with details
            VStack(spacing: 4) {
                ForEach(todaySessions.suffix(30).reversed()) { session in
                    debugSessionRow(session: session)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    var debugTimelineView: some View {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        let dayDuration = now.timeIntervalSince(startOfDay)
        let scale: CGFloat = 1200 / CGFloat(dayDuration)  // pixels per second
        
        return ZStack(alignment: .topLeading) {
            // Hour markers
            ForEach(0..<24, id: \.self) { hour in
                let x = CGFloat(hour * 3600) * scale
                VStack {
                    Text("\(hour)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1, height: 180)
                }
                .offset(x: x)
            }
            
            // Sessions
            ForEach(Array(todaySessions.enumerated()), id: \.element.id) { index, session in
                let startOffset = session.startTimestamp.timeIntervalSince(startOfDay)
                let duration = session.duration
                let x = CGFloat(startOffset) * scale
                let width = max(2, CGFloat(duration) * scale)
                let y: CGFloat = CGFloat(index % 10) * 15 + 15
                
                let isCounted = session.activityType != .meta && !excludedBundleIDs.contains(session.bundleID)
                
                Rectangle()
                    .fill(isCounted ? colorForActivityType(session.activityType) : .gray.opacity(0.3))
                    .frame(width: width, height: 12)
                    .offset(x: x, y: y)
                    .help("\(session.appName): \(formatDuration(session.duration))")
            }
        }
        .frame(width: 1200)
    }
    
    func debugSessionRow(session: Session) -> some View {
        let isCounted = session.activityType != .meta && !excludedBundleIDs.contains(session.bundleID)
        let startTime = session.startTimestamp.formatted(date: .omitted, time: .shortened)
        let endTime = (session.endTimestamp ?? Date()).formatted(date: .omitted, time: .shortened)
        
        return HStack(spacing: 8) {
            Circle()
                .fill(isCounted ? colorForActivityType(session.activityType) : .gray)
                .frame(width: 6, height: 6)
            
            Text(session.appName)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            
            Text("\(startTime) - \(endTime)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Text(formatDuration(session.duration))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            
            Text(session.activityType.rawValue)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .background(isCounted ? .blue.opacity(0.2) : .gray.opacity(0.2))
                .clipShape(Capsule())
            
            if !isCounted {
                Text("EXCLUDED")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
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
}

// MARK: - Category Pill
struct CategoryPill: View {
    let name: String
    let duration: TimeInterval
    let color: Color
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color.gradient)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.4), radius: isHovered ? 6 : 2)
            
            Text(formatDuration(duration))
                .font(.caption.bold())
                .contentTransition(.numericText())
            
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Hourly Bar Chart
struct HourlyBarChart: View {
    let sessions: [Session]
    
    var body: some View {
        GeometryReader { geo in
            let hourlyData = computeHourlyData()
            let maxMinutes = hourlyData.values.max() ?? 60
            let barWidth = geo.size.width / 24 - 2
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let minutes = hourlyData[hour] ?? 0
                    let height = maxMinutes > 0 ? CGFloat(minutes / maxMinutes) * (geo.size.height - 20) : 0
                    
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorForHour(hour).gradient)
                            .frame(width: barWidth, height: max(height, 2))
                        
                        if hour % 6 == 0 {
                            Text("\(hour)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("")
                                .font(.system(size: 8))
                        }
                    }
                }
            }
        }
    }
    
    func computeHourlyData() -> [Int: Double] {
        var data: [Int: Double] = [:]
        let calendar = Calendar.current
        
        for session in sessions where session.state == .active {
            let hour = calendar.component(.hour, from: session.startTimestamp)
            data[hour] = (data[hour] ?? 0) + session.duration / 60.0
        }
        
        return data
    }
    
    func colorForHour(_ hour: Int) -> Color {
        // Morning blue, afternoon green, evening purple, night gray
        switch hour {
        case 6..<12: return .blue
        case 12..<17: return .green
        case 17..<21: return .purple
        default: return .gray
        }
    }
}

// MARK: - App Usage Row
struct AppUsageRow: View {
    let appName: String
    let bundleID: String
    let duration: TimeInterval
    let activityType: ActivityType
    let maxDuration: TimeInterval
    let domainBreakdown: [ScreenTimeView.DomainUsageData]
    
    @State private var isExpanded = false
    @State private var isHovered = false
    
    var isBrowser: Bool {
        activityType == .browser && !domainBreakdown.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainRow
            
            if isBrowser && isExpanded {
                domainList
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.03) : .clear)
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    var mainRow: some View {
        HStack(spacing: 12) {
            // Real App Icon
            AppIconView(bundleID: bundleID, size: 40)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appName)
                        .font(.subheadline.bold())
                    
                    if isBrowser {
                        Text("\(domainBreakdown.count) sites")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    Text(formatDuration(duration))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if isBrowser {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorForActivityType.gradient)
                            .frame(width: CGFloat(duration / maxDuration) * geo.size.width, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isBrowser {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }
    
    var domainList: some View {
        VStack(spacing: 2) {
            ForEach(domainBreakdown.prefix(5)) { domain in
                HStack(spacing: 8) {
                    // Favicon
                    AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(domain.domain)&sz=32")) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Circle().fill(.gray.opacity(0.3))
                    }
                    .frame(width: 14, height: 14)
                    
                    Text(domain.domain)
                        .font(.caption)
                        .foregroundStyle(domain.isDistraction ? .red : .secondary)
                    
                    Spacer()
                    
                    Text(formatDuration(domain.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 52)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 8)
    }
    
    var colorForActivityType: Color {
        switch activityType {
        case .focusedWork: return .blue
        case .communication: return .indigo
        case .browser: return .cyan
        case .entertainment: return .pink
        case .admin: return .mint
        case .referenceLearning: return .orange
        default: return .gray
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Domain As App Row
struct DomainAsAppRow: View {
    let domain: String
    let duration: TimeInterval
    let isDistraction: Bool
    let maxDuration: TimeInterval
    
    var body: some View {
        HStack(spacing: 12) {
            // Favicon placeholder (globe for now)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDistraction ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: isDistraction ? "exclamationmark.triangle.fill" : "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(isDistraction ? .red : .blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(domain)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(isDistraction ? .red : .primary)
                    .lineLimit(1)
                
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Progress bar
            GeometryReader { geo in
                let width = min(geo.size.width, geo.size.width * CGFloat(duration / maxDuration))
                Capsule()
                    .fill((isDistraction ? Color.red : Color.blue).opacity(0.3))
                    .frame(width: width, height: 6)
            }
            .frame(width: 80, height: 6)
        }
        .padding(.vertical, 4)
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

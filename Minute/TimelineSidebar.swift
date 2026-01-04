//
//  TimelineSidebar.swift
//  Minute
//
//  Dock-style sidebar timeline with non-linear scaling
//  6-hour visible window, 1-hour focus = 50% of height
//

import SwiftUI
import Combine

struct TimelineSidebar: View {
    let sessions: [Session]
    
    /// Optional binding to highlight and sync with main content
    @Binding var selectedSession: Session?
    
    // MARK: - Configuration
    
    /// Total visible window in minutes (6 hours)
    let visibleWindowMinutes: Double = 360
    
    /// Minutes in the focus window (high detail) - takes 50% of height
    let focusSpanMinutes: Double = 60
    
    /// How "dock-like" the magnification feels - higher = more extreme
    /// With 1hr taking 50% of 6hr view, we need ~5x magnification at center
    let magnificationStrength: Double = 4.0
    
    /// Minimum session duration to show
    let minDuration: TimeInterval = 30
    
    // MARK: - State
    
    /// Current focus center (where magnification is centered)
    @State private var focusCenter: Date = Date()
    
    /// Whether we're following "now" or pinned
    @State private var isNowFollowing: Bool = true
    
    /// Hover preview state
    @State private var hoverTime: Date?
    @State private var showingPreview: Bool = false
    
    // Timer to update "now"
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // Top controls
            topControls
            
            // Main timeline
            GeometryReader { geo in
                timelineContent(height: geo.size.height)
            }
            
            // Bottom legend
            bottomLegend
        }
        .frame(width: 100)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear, .black.opacity(0.02)],
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
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onReceive(timer) { _ in
            if isNowFollowing {
                focusCenter = Date()
            }
        }
        // Keyboard navigation
        .onKeyPress(.downArrow) {
            nudgeFocus(by: 15)  // 15 minutes forward
            return .handled
        }
        .onKeyPress(.upArrow) {
            nudgeFocus(by: -15)  // 15 minutes back
            return .handled
        }
        .onKeyPress("j") {
            nudgeFocus(by: 15)
            return .handled
        }
        .onKeyPress("k") {
            nudgeFocus(by: -15)
            return .handled
        }
        .onKeyPress("n") {
            withAnimation(.spring(response: 0.3)) {
                focusCenter = Date()
                isNowFollowing = true
            }
            return .handled
        }
    }
    
    func nudgeFocus(by minutes: Int) {
        let newTime = focusCenter.addingTimeInterval(Double(minutes) * 60)
        let clamped = clampFocusCenter(newTime)
        withAnimation(.spring(response: 0.2)) {
            focusCenter = clamped
            isNowFollowing = false
        }
    }
    
    // MARK: - Top Controls
    
    var topControls: some View {
        VStack(spacing: 4) {
            // Date
            Text(Date(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            
            // Jump buttons
            HStack(spacing: 2) {
                jumpButton("Now", systemImage: "circle.fill") {
                    withAnimation(.spring(response: 0.3)) {
                        focusCenter = Date()
                        isNowFollowing = true
                    }
                }
                
                jumpButton("AM", systemImage: nil) {
                    jumpTo(hour: 9)
                }
                
                jumpButton("PM", systemImage: nil) {
                    jumpTo(hour: 14)
                }
                
                jumpButton("Eve", systemImage: nil) {
                    jumpTo(hour: 19)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
    
    func jumpButton(_ label: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 6))
                } else {
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                }
            }
            .frame(width: 22, height: 16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.pressScale)
    }
    
    func jumpTo(hour: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let target = calendar.date(byAdding: .hour, value: hour, to: today) {
            withAnimation(.spring(response: 0.3)) {
                focusCenter = target
                isNowFollowing = false
            }
        }
    }
    
    // MARK: - Timeline Content
    
    func timelineContent(height: CGFloat) -> some View {
        let now = Date()
        
        return ZStack(alignment: .topLeading) {
            // Hour grid with non-linear scaling
            hourGrid(height: height)
            
            // Session blocks
            sessionBlocks(height: height, now: now)
            
            // Current time indicator
            currentTimeIndicator(height: height, now: now)
            
            // "Return to Now" pill (when pinned)
            if !isNowFollowing {
                returnToNowPill
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let time = timeFromY(value.location.y, height: height)
                    let clamped = clampFocusCenter(time)
                    withAnimation(.interactiveSpring(response: 0.15)) {
                        focusCenter = clamped
                        isNowFollowing = false
                    }
                }
        )
        .onTapGesture { location in
            let time = timeFromY(location.y, height: height)
            let clamped = clampFocusCenter(time)
            withAnimation(.spring(response: 0.3)) {
                focusCenter = clamped
                isNowFollowing = false
            }
        }
    }
    
    /// Clamp focus center to reasonable bounds (6am today to now)
    func clampFocusCenter(_ time: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .hour, value: 6, to: today)!  // 6am
        let latest = Date()  // Now
        
        return min(latest, max(earliest, time))
    }
    
    // MARK: - Non-Linear Scale Function
    
    /// Maps time distance from focus center to pixels-per-minute
    /// Uses a Gaussian-like falloff for smooth dock effect
    func magnification(for time: Date) -> Double {
        let distanceMinutes = abs(time.timeIntervalSince(focusCenter)) / 60
        
        // Gaussian-style falloff with tighter sigma for more pronounced effect
        let sigma = focusSpanMinutes / 2.5
        let exponent = -pow(distanceMinutes, 2) / (2 * pow(sigma, 2))
        let gaussianFactor = exp(exponent)
        
        // Scale from 1.0 (base) to (1 + magnificationStrength) at center
        return 1.0 + magnificationStrength * gaussianFactor
    }
    
    /// Visible window boundaries (6 hours centered on focusCenter)
    var visibleWindowStart: Date {
        focusCenter.addingTimeInterval(-visibleWindowMinutes * 30)  // 3 hours before
    }
    
    var visibleWindowEnd: Date {
        focusCenter.addingTimeInterval(visibleWindowMinutes * 30)   // 3 hours after
    }
    
    /// Convert time to Y position using non-linear scale within visible window
    func yPosition(for time: Date, height: CGFloat) -> CGFloat {
        let windowStart = visibleWindowStart
        let windowEnd = visibleWindowEnd
        
        // Clamp time to visible window
        let clampedTime = min(max(time, windowStart), windowEnd)
        
        // Integrate magnification within visible window
        let steps = 72  // 5-minute increments over 6 hours
        let stepDuration: TimeInterval = visibleWindowMinutes * 60 / Double(steps)
        var totalMagnification: Double = 0
        var targetMagnification: Double = 0
        
        for i in 0..<steps {
            let stepTime = windowStart.addingTimeInterval(Double(i) * stepDuration)
            let stepMag = magnification(for: stepTime)
            totalMagnification += stepMag
            
            if stepTime <= clampedTime {
                targetMagnification += stepMag
            }
        }
        
        return height * CGFloat(targetMagnification / max(1, totalMagnification))
    }
    
    /// Convert Y position back to time (inverse of yPosition)
    func timeFromY(_ y: CGFloat, height: CGFloat) -> Date {
        let fraction = max(0, min(1, y / height))
        let windowStart = visibleWindowStart
        
        let steps = 72
        let stepDuration: TimeInterval = visibleWindowMinutes * 60 / Double(steps)
        var totalMagnification: Double = 0
        
        for i in 0..<steps {
            let stepTime = windowStart.addingTimeInterval(Double(i) * stepDuration)
            totalMagnification += magnification(for: stepTime)
        }
        
        let targetMag = Double(fraction) * totalMagnification
        var accumulatedMag: Double = 0
        
        for i in 0..<steps {
            let stepTime = windowStart.addingTimeInterval(Double(i) * stepDuration)
            accumulatedMag += magnification(for: stepTime)
            if accumulatedMag >= targetMag {
                return stepTime
            }
        }
        
        return visibleWindowEnd
    }
    
    // MARK: - Hour Grid
    
    struct HourItem: Identifiable {
        let id: Int
        var hour: Int { id }
    }
    
    func hourGrid(height: CGFloat) -> some View {
        // Show hours within visible window
        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: visibleWindowStart)
        let endHour = calendar.component(.hour, from: visibleWindowEnd)
        let hours = stride(from: startHour, through: min(endHour, 23), by: 1).map { HourItem(id: $0) }
        
        return ZStack(alignment: .topLeading) {
            ForEach(hours) { item in
                hourRow(hour: item.hour, height: height)
            }
        }
    }
    
    @ViewBuilder
    func hourRow(hour: Int, height: CGFloat) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let hourTime = calendar.date(byAdding: .hour, value: hour, to: today)!
        let y = yPosition(for: hourTime, height: height)
        let mag = magnification(for: hourTime)
        
        HStack(spacing: 2) {
            Text(hourLabel(hour))
                .font(.system(size: mag > 2 ? 10 : 7, weight: .medium, design: .monospaced))
                .foregroundStyle(mag > 2 ? .primary : .tertiary)
                .frame(width: 22, alignment: .trailing)
            
            Rectangle()
                .fill(Color.secondary.opacity(mag > 2 ? 0.3 : 0.15))
                .frame(height: 0.5)
        }
        .offset(y: y)
    }
    
    func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }
    
    // MARK: - Session Blocks
    
    func sessionBlocks(height: CGFloat, now: Date) -> some View {
        let filtered = significantSessions.filter { session in
            // Only show sessions within visible window
            let end = session.endTimestamp ?? now
            return session.startTimestamp < visibleWindowEnd && end > visibleWindowStart
        }
        
        return ZStack(alignment: .topLeading) {
            ForEach(filtered, id: \.id) { session in
                let startY = yPosition(for: session.startTimestamp, height: height)
                let endTime = session.endTimestamp ?? now
                let endY = yPosition(for: endTime, height: height)
                let mag = magnification(for: session.startTimestamp)
                let isSelected = selectedSession?.id == session.id
                
                // Minimum height based on magnification - bigger in focus region
                let minHeight: CGFloat = mag > 2 ? 20 : 8
                let blockHeight = max(minHeight, endY - startY - 2)  // -2 for gap
                
                sessionBlock(session: session, magnification: mag, isSelected: isSelected)
                    .frame(height: blockHeight)
                    .offset(x: 26, y: startY)
                    .onTapGesture {
                        selectedSession = session
                    }
            }
        }
    }
    
    func sessionBlock(session: Session, magnification: Double, isSelected: Bool) -> some View {
        let isDistraction = DistractionRules.isDistraction(session: session)
        let color = colorForSession(session)
        let showDetail = magnification > 1.4
        
        return SessionBlockView(
            session: session,
            color: color,
            isDistraction: isDistraction,
            showDetail: showDetail,
            isSelected: isSelected,
            tooltip: sessionTooltip(session)
        )
    }
    
    func sessionTooltip(_ session: Session) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let startTime = formatter.string(from: session.startTimestamp)
        let duration = formatDuration(session.duration)
        
        var tooltip = "\(session.appName)\n\(startTime) • \(duration)"
        if let domain = session.browserDomain {
            tooltip += "\n\(domain)"
        }
        if DistractionRules.isDistraction(session: session) {
            tooltip += "\n⚠️ Distraction"
        }
        return tooltip
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
    
    // MARK: - Current Time Indicator
    
    func currentTimeIndicator(height: CGFloat, now: Date) -> some View {
        let y = yPosition(for: now, height: height)
        
        return NowIndicatorView()
            .offset(x: 20, y: y - 4)
    }
    
    // MARK: - Return to Now Pill
    
    var returnToNowPill: some View {
        VStack {
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    focusCenter = Date()
                    isNowFollowing = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                    Text("Now")
                        .font(.system(size: 9, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bottom Legend
    
    var bottomLegend: some View {
        HStack(spacing: 4) {
            Circle().fill(.blue).frame(width: 6, height: 6)
            Text("Work")
            Circle().fill(.cyan).frame(width: 6, height: 6)
            Text("Browse")
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("Loss")
        }
        .font(.system(size: 6))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
    
    // MARK: - Data Helpers
    
    var significantSessions: [Session] {
        sessions
            .filter { $0.state == .active && $0.duration >= minDuration }
            .sorted { $0.startTimestamp < $1.startTimestamp }
    }
    
    func colorForSession(_ session: Session) -> Color {
        switch session.activityType {
        case .focusedWork: return .blue
        case .communication: return .indigo
        case .browser: return .cyan
        case .entertainment: return .pink
        case .admin: return .mint
        case .referenceLearning: return .orange
        default: return .gray
        }
    }
}

// MARK: - Session Block View with Hover Glow

struct SessionBlockView: View {
    let session: Session
    let color: Color
    let isDistraction: Bool
    let showDetail: Bool
    let isSelected: Bool
    let tooltip: String
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 2) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill((isDistraction ? Color.red : color).gradient)
                .frame(width: showDetail ? 4 : 3)
            
            // Label (only in focus region)
            if showDetail {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.appName)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                    
                    if let domain = session.browserDomain {
                        Text(domain)
                            .font(.system(size: 6))
                            .foregroundStyle(isDistraction ? .red : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(showDetail ? 0.15 : 0.1))
        )
        .overlay(
            // Selection or distraction indicator
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isSelected ? .blue : (isDistraction ? .red.opacity(0.4) : .clear),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: isHovered ? color.opacity(0.3) : .clear,
            radius: isHovered ? 6 : 0
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

// MARK: - Now Indicator with Pulse

struct NowIndicatorView: View {
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? 6 : 2)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
            
            Rectangle()
                .fill(.red)
                .frame(height: 2)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}

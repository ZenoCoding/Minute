//
//  ZoomTimelineView.swift
//  Minute
//
//  Dual-scale timeline: day overview + zoomed past hour
//

import SwiftUI

struct ZoomTimelineView: View {
    let sessions: [Session]
    
    // Zoom state
    @State private var zoomCenter: Date = Date()
    @State private var zoomWindowMinutes: Double = 60  // How many minutes visible in zoom
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Day overview strip (left)
                dayOverviewStrip
                    .frame(width: 40)
                
                // Zoom window (center)
                zoomWindow
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Day Overview Strip
    
    var dayOverviewStrip: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                
                // Hour markers
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        let height = geo.size.height / 24
                        
                        ZStack(alignment: .leading) {
                            // Activity density for this hour
                            let density = activityDensity(for: hour)
                            Rectangle()
                                .fill(densityGradient(density))
                                .frame(height: height)
                            
                            // Hour label (every 6 hours)
                            if hour % 6 == 0 {
                                Text("\(hour)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                }
                
                // Zoom indicator
                let (top, height) = zoomIndicatorPosition(in: geo.size.height)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.blue, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.1)))
                    .frame(height: height)
                    .offset(y: top - geo.size.height / 2 + height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Convert Y position to time
                        let calendar = Calendar.current
                        let startOfDay = calendar.startOfDay(for: Date())
                        let hoursFraction = Double(value.location.y / geo.size.height) * 24
                        let newCenter = calendar.date(byAdding: .second, value: Int(hoursFraction * 3600), to: startOfDay)!
                        
                        // Clamp to reasonable range
                        let now = Date()
                        withAnimation(.interactiveSpring(response: 0.2)) {
                            zoomCenter = min(now, max(startOfDay, newCenter))
                        }
                    }
            )
            .onTapGesture { location in
                // Jump to tapped hour
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                let hoursFraction = Double(location.y / geo.size.height) * 24
                let newCenter = calendar.date(byAdding: .second, value: Int(hoursFraction * 3600), to: startOfDay)!
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    zoomCenter = newCenter
                }
            }
        }
    }
    
    // MARK: - Zoom Window
    
    var zoomWindow: some View {
        GeometryReader { geo in
            let zoomSessions = sessionsInZoomWindow()
            
            ZStack {
                // Background with glassmorphism
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                
                if zoomSessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("No activity in this window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(zoomSessions, id: \.id) { session in
                                sessionCard(for: session, maxWidth: geo.size.width - 24)
                            }
                        }
                        .padding(12)
                    }
                }
                
                // Time labels + zoom controls overlay
                VStack {
                    HStack {
                        Text(zoomWindowStart, style: .time)
                            .font(.caption2.monospacedDigit())
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        
                        Spacer()
                        
                        // Zoom controls
                        HStack(spacing: 4) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    zoomWindowMinutes = min(180, zoomWindowMinutes * 1.5)  // Zoom out
                                }
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.caption)
                                    .padding(4)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            
                            Text("\(Int(zoomWindowMinutes))m")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 35)
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    zoomWindowMinutes = max(15, zoomWindowMinutes / 1.5)  // Zoom in
                                }
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.caption)
                                    .padding(4)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(8)
                    
                    Spacer()
                    
                    HStack {
                        Text(zoomWindowEnd, style: .time)
                            .font(.caption2.monospacedDigit())
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.leading, 8)
    }
    
    // MARK: - Session Card
    
    func sessionCard(for session: Session, maxWidth: CGFloat) -> some View {
        let isDistraction = DistractionRules.isDistraction(session: session)
        let color = colorForSession(session)
        
        return HStack(spacing: 10) {
            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startTimestamp, style: .time)
                    .font(.caption2.monospacedDigit())
                Text(formatDuration(session.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, alignment: .trailing)
            
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(color.gradient)
                .frame(width: 4)
            
            // App info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.appName)
                        .font(.caption.bold())
                    
                    if let domain = session.browserDomain {
                        Text(domain)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(isDistraction ? .red.opacity(0.15) : .gray.opacity(0.1))
                            .foregroundStyle(isDistraction ? .red : .secondary)
                            .clipShape(Capsule())
                    }
                }
                
                Text(session.activityType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDistraction ? .red.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
    
    func timeLabelsOverlay(height: CGFloat) -> some View {
        let zoomStart = zoomWindowStart
        let zoomEnd = zoomWindowEnd
        
        return ZStack(alignment: .topLeading) {
            // Start time
            Text(zoomStart, style: .time)
                .font(.caption2.monospacedDigit())
                .padding(4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .offset(x: 8, y: 8)
            
            // End time (now)
            VStack {
                Spacer()
                Text(zoomEnd, style: .time)
                    .font(.caption2.monospacedDigit())
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: 8, y: -8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Data Helpers
    
    var zoomWindowStart: Date {
        zoomCenter.addingTimeInterval(-zoomWindowMinutes * 30)  // Half before center
    }
    
    var zoomWindowEnd: Date {
        zoomCenter.addingTimeInterval(zoomWindowMinutes * 30)   // Half after center
    }
    
    func sessionsInZoomWindow() -> [Session] {
        let start = zoomWindowStart
        let end = zoomWindowEnd
        
        return sessions
            .filter { session in
                let sessionEnd = session.endTimestamp ?? Date()
                return session.startTimestamp < end && sessionEnd > start
            }
            .filter { $0.state == .active }
            .sorted { $0.startTimestamp < $1.startTimestamp }
    }
    
    func activityDensity(for hour: Int) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let hourStart = calendar.date(byAdding: .hour, value: hour, to: today)!
        let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
        
        let minutesActive = sessions
            .filter { session in
                let sessionEnd = session.endTimestamp ?? Date()
                return session.startTimestamp < hourEnd && sessionEnd > hourStart && session.state == .active
            }
            .reduce(0.0) { $0 + $1.duration }
        
        return min(1.0, minutesActive / 3600.0)  // Normalize to 0-1 based on how full the hour is
    }
    
    func densityGradient(_ density: Double) -> Color {
        if density < 0.1 { return .clear }
        if density < 0.3 { return .green.opacity(0.2) }
        if density < 0.6 { return .green.opacity(0.4) }
        return .green.opacity(0.6)
    }
    
    func zoomIndicatorPosition(in totalHeight: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        let zoomStartHours = zoomWindowStart.timeIntervalSince(startOfDay) / 3600
        let zoomEndHours = zoomWindowEnd.timeIntervalSince(startOfDay) / 3600
        
        let pixelsPerHour = totalHeight / 24
        let top = CGFloat(zoomStartHours) * pixelsPerHour
        let height = CGFloat(zoomEndHours - zoomStartHours) * pixelsPerHour
        
        return (max(0, top), min(height, totalHeight - top))
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
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

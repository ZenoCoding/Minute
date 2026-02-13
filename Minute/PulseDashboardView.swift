//
//  PulseDashboardView.swift
//  Minute
//
//  The high-signal "Heads Up" display for your day.
//  Replaces the static Areas grid as the daily driver.
//

import SwiftUI
import SwiftData
import EventKit
import Combine
import AppKit

struct PulseDashboardView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @Query(sort: \Area.orderIndex) private var areas: [Area]
    @State private var now = Date()
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // Navigation to Areas
    let onNavigateToAreas: () -> Void

    private var hasCalendarAccess: Bool {
        calendarManager.authorizationStatus == .fullAccess || calendarManager.authorizationStatus == .writeOnly
    }

    private var scheduleHighlights: [CalendarHighlight] {
        calendarManager.highlights(for: now, now: now)
    }

    private var todayEvents: [EKEvent] {
        calendarManager.todayEvents(for: now, now: now)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                
                // Date Header
                HStack {
                    Text(now, format: .dateTime.weekday(.wide).month().day())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today at a Glance")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if hasCalendarAccess {
                        ScheduleHighlightsCard(
                            highlights: scheduleHighlights,
                            todayEvents: todayEvents,
                            onOpenCalendar: openCalendarApp
                        )
                    } else if calendarManager.authorizationStatus == .notDetermined {
                        Button("Connect Calendar") {
                            calendarManager.requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Calendar access is off. Enable it in System Settings to show highlights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                
                // Areas Summary (Navigation Entry)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Areas & Projects")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Manage All", action: onNavigateToAreas)
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(areas) { area in
                                AreaCompactCard(area: area)
                            }
                            
                            Button(action: onNavigateToAreas) {
                                VStack {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.title2)
                                    Text("View All")
                                        .font(.caption)
                                }
                                .frame(width: 100, height: 100)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                }
                
                Spacer()
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            now = Date()
            if hasCalendarAccess {
                calendarManager.fetchEvents()
            }
        }
        .onReceive(minuteTimer) { date in
            now = date
        }
        .onChange(of: calendarManager.authorizationStatus) { _, status in
            if status == .fullAccess || status == .writeOnly {
                calendarManager.fetchEvents()
            }
        }
    }

    private func openCalendarApp() {
        guard let url = URL(string: "calshow:\(now.timeIntervalSinceReferenceDate)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct AreaCompactCard: View {
    let area: Area
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: area.iconName)
                .font(.title2)
                .foregroundStyle(Color(hex: area.themeColor) ?? .blue)
            
            Text(area.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("\(area.projects.filter { $0.status == .active }.count) projects")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 110)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

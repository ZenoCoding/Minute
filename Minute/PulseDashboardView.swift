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
    @Query(sort: \TaskItem.orderIndex) private var tasks: [TaskItem]
    @AppStorage(DayCapacitySettings.useFallbackDurationKey) private var useFallbackDuration = false
    @AppStorage(DayCapacitySettings.fallbackDurationMinutesKey) private var fallbackDurationMinutes = DayCapacitySettings.defaultFallbackDurationMinutes
    @AppStorage(DayCapacitySettings.sleepWeekdayWakeMinutesKey) private var sleepWeekdayWakeMinutes = DayCapacitySettings.defaultSleepWeekdayWakeMinutes
    @AppStorage(DayCapacitySettings.sleepWeekdayBedMinutesKey) private var sleepWeekdayBedMinutes = DayCapacitySettings.defaultSleepWeekdayBedMinutes
    @AppStorage(DayCapacitySettings.sleepWeekendWakeMinutesKey) private var sleepWeekendWakeMinutes = DayCapacitySettings.defaultSleepWeekendWakeMinutes
    @AppStorage(DayCapacitySettings.sleepWeekendBedMinutesKey) private var sleepWeekendBedMinutes = DayCapacitySettings.defaultSleepWeekendBedMinutes
    @State private var now = Date()
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let dayCapacityService = DayCapacityService()
    
    // Navigation to Areas
    let onNavigateToAreas: () -> Void

    private var hasCalendarAccess: Bool {
        calendarManager.canReadEvents
    }

    private var scheduleHighlights: [CalendarHighlight] {
        calendarManager.highlights(for: now, now: now)
    }

    private var tomorrowDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    private var todayEvents: [EKEvent] {
        calendarManager.todayEvents(for: now, now: now)
    }

    private var tomorrowEvents: [EKEvent] {
        calendarManager.tomorrowEvents(from: now, now: now)
    }

    private var nextEvent: EKEvent? {
        calendarManager.nextEvent(after: now)
    }

    private var todayBusySeconds: TimeInterval {
        calendarManager.busySeconds(on: now, now: now)
    }

    private var tomorrowBusySeconds: TimeInterval {
        calendarManager.busySeconds(on: tomorrowDate, now: now)
    }

    private var sleepSchedule: SleepSchedule {
        SleepSchedule(
            weekdayWakeMinutes: sleepWeekdayWakeMinutes,
            weekdayBedMinutes: sleepWeekdayBedMinutes,
            weekendWakeMinutes: sleepWeekendWakeMinutes,
            weekendBedMinutes: sleepWeekendBedMinutes
        )
    }

    private var forecastDayInputs: [DayCapacityForecastDayInput] {
        let classifier = SleepAwareDayClassifier()
        let activeWindow = classifier.planningWindow(for: now, schedule: sleepSchedule)

        return (0..<7).map { offset in
            let window = offset == 0
                ? activeWindow
                : classifier.planningWindow(after: activeWindow, offset: offset, schedule: sleepSchedule)
            let busyIntervals = hasCalendarAccess
                ? calendarManager.busyIntervals(in: DateInterval(start: window.start, end: window.end))
                : []
            return DayCapacityForecastDayInput(window: window, busyIntervals: busyIntervals)
        }
    }

    private var forecast: DayCapacityForecast {
        dayCapacityService.forecast(
            now: now,
            tasks: tasks,
            dayInputs: forecastDayInputs,
            useFallbackDuration: useFallbackDuration,
            fallbackDurationMinutes: fallbackDurationMinutes
        )
    }

    private var forecastHeadline: String {
        if !forecast.hasDatedTasks {
            return "No deadlines this week"
        }

        if let overloadedDay = forecast.days.first(where: { $0.status == .overloaded }) {
            return "Overloaded on \(forecastDayName(overloadedDay.planningWindow.labelDate))"
        }

        if let tightDay = forecast.days.first(where: { $0.status == .tight }) {
            return "Tight on \(forecastDayName(tightDay.planningWindow.labelDate))"
        }

        return "Capacity looks steady"
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
                            now: now,
                            highlights: scheduleHighlights,
                            todayEvents: todayEvents,
                            tomorrowEvents: tomorrowEvents,
                            nextEvent: nextEvent,
                            todayBusySeconds: todayBusySeconds,
                            tomorrowBusySeconds: tomorrowBusySeconds,
                            onOpenCalendarDay: openCalendarApp
                        )
                    } else if calendarManager.authorizationStatus == .notDetermined {
                        Button("Connect Calendar") {
                            calendarManager.requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if calendarManager.authorizationStatus == .writeOnly {
                        Text("Calendar access is set to Add Only. Enable Full Access in System Settings to show schedule highlights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("Calendar access is off. Enable Full Access in System Settings to show highlights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)

                SevenDayForecastCard(
                    forecast: forecast,
                    hasCalendarAccess: hasCalendarAccess,
                    calendarAccessStatus: calendarManager.authorizationStatus,
                    headline: forecastHeadline
                )
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
            if status == .fullAccess {
                calendarManager.fetchEvents()
            }
        }
    }

    private func openCalendarApp(for date: Date) {
        guard let url = URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func forecastDayName(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

struct SevenDayForecastCard: View {
    let forecast: DayCapacityForecast
    let hasCalendarAccess: Bool
    let calendarAccessStatus: EKAuthorizationStatus
    let headline: String
    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isShowingDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    if !isActionableWeek {
                        if forecast.days.isEmpty {
                            Text("Sleep-aware work windows are unavailable right now.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForecastWeekStrip(days: forecast.days)
                        }
                    }

                    if forecast.hasDatedTasks {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Project timing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(sortedCohorts) { cohort in
                                ForecastCohortDetailRow(cohort: cohort)
                            }
                        }
                    }

                    if !hasCalendarAccess || forecast.hasUnknownDurations {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !hasCalendarAccess {
                                Label("Calendar estimate", systemImage: "calendar")
                                    .help(calendarDescription)
                                    .accessibilityLabel(calendarDescription)
                            }

                            if forecast.hasUnknownDurations {
                                Label(unknownDurationLabel, systemImage: "questionmark.circle")
                                    .help(unknownDurationText)
                                    .accessibilityLabel(unknownDurationText)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Next 7 days")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    Text(compactStatusText)
                        .font(.caption.weight(isActionableWeek ? .semibold : .medium))
                        .foregroundStyle(isActionableWeek ? accentColor : .secondary)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Next 7 days, \(compactStatusText)")
                .accessibilityValue(accessibilitySummary)
                .accessibilityHint("Expand for daily pressure, project timing, and forecast caveats.")
                .help(accessibilitySummary)
            }
            .tint(.secondary)

            if isActionableWeek {
                if let focusLine {
                    HStack(spacing: 6) {
                        Image(systemName: focusLineSymbol)
                            .font(.caption2.weight(.semibold))
                        Text(focusLine)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(focusLineColor)
                }

                if forecast.days.isEmpty {
                    Text("Forecast unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForecastWeekStrip(days: forecast.days)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surfaceTint)
            }
        }
    }

    private var accentColor: Color {
        if forecast.days.contains(where: { $0.status == .overloaded }) {
            return .red
        }
        if forecast.days.contains(where: { $0.status == .tight }) {
            return .orange
        }
        return .accentColor
    }

    private var surfaceTint: Color {
        isActionableWeek ? accentColor.opacity(0.045) : Color.secondary.opacity(0.025)
    }

    private var hasPressure: Bool {
        forecast.days.contains { $0.status == .tight || $0.status == .overloaded }
    }

    private var isActionableWeek: Bool {
        hasPressure || hasImmediateFocus
    }

    private var hasImmediateFocus: Bool {
        guard let focusCohort else { return false }
        if focusCohort.isInsufficientCapacity {
            return true
        }
        guard
            let startDate = focusCohort.latestSafeStartDate,
            let firstDay = forecast.days.first?.planningWindow.labelDate,
            let endOfTomorrow = Calendar.current.date(
                byAdding: .day,
                value: 2,
                to: Calendar.current.startOfDay(for: firstDay)
            )
        else {
            return false
        }
        return startDate < endOfTomorrow
    }

    private var compactStatusText: String {
        if forecast.days.isEmpty {
            return "Unavailable"
        }
        return isActionableWeek ? headline : "No known crunch"
    }

    private var summaryText: String {
        let knownDueSeconds = forecast.days.reduce(0) { $0 + $1.dueOnDaySeconds }
        let availableSeconds = forecast.days.reduce(0) { $0 + $1.availableSecondsForDeadlines }
        let availableText = "\(formatDuration(availableSeconds)) free"

        if knownDueSeconds > 0 {
            let dueText = "\(formatDuration(knownDueSeconds)) due"
            return "\(dueText) · \(availableText)"
        }

        return availableText
    }

    private var focusCohort: DayCapacityForecastCohort? {
        forecast.cohorts
            .filter { $0.latestSafeStartDate != nil || $0.isInsufficientCapacity }
            .sorted {
                let lhs = $0.latestSafeStartDate ?? $0.deadlineDate
                let rhs = $1.latestSafeStartDate ?? $1.deadlineDate
                if lhs != rhs { return lhs < rhs }
                return $0.deadlineDate < $1.deadlineDate
            }
            .first
    }

    private var focusLine: String? {
        guard let focusCohort else { return nil }
        if focusCohort.isInsufficientCapacity {
            return "No safe start for \(focusCohort.project.displayName)"
        }
        guard let latestSafeStartDate = focusCohort.latestSafeStartDate else { return nil }
        return "Start \(focusCohort.project.displayName) by \(shortDate(latestSafeStartDate))"
    }

    private var focusLineSymbol: String {
        focusCohort?.isInsufficientCapacity == true ? "exclamationmark.triangle.fill" : "arrow.right"
    }

    private var focusLineColor: Color {
        if focusCohort?.isInsufficientCapacity == true || forecast.days.contains(where: { $0.status == .overloaded }) {
            return .red
        }
        if forecast.days.contains(where: { $0.status == .tight }) {
            return .orange
        }
        return .secondary
    }

    private var accessibilitySummary: String {
        var details: [String] = [headline]
        if let focusLine {
            details.append(focusLine)
        }
        if forecast.hasDatedTasks {
            details.append(summaryText)
        }
        details.append(calendarDescription)
        if forecast.hasUnknownDurations {
            details.append(unknownDurationText)
        }
        return details.joined(separator: ". ")
    }

    private var calendarDescription: String {
        if hasCalendarAccess {
            return "Calendar included"
        }
        switch calendarAccessStatus {
        case .notDetermined:
            return "Calendar not connected; free time is an estimate"
        case .writeOnly:
            return "Calendar is Add Only; commitments are not visible"
        default:
            return "Calendar access is off; free time is an estimate"
        }
    }

    private var unknownDurationText: String {
        let count = forecast.unknownDurationCount
        let noun = count == 1 ? "duration" : "durations"
        if forecast.usesFallbackDuration {
            return "\(count) unknown \(noun) estimated"
        }
        return "\(count) unknown \(noun) not counted"
    }

    private var unknownDurationLabel: String {
        "\(forecast.unknownDurationCount) unknown"
    }

    private var sortedCohorts: [DayCapacityForecastCohort] {
        forecast.cohorts.sorted { $0.deadlineDate < $1.deadlineDate }
    }

    private func shortDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct ForecastWeekStrip: View {
    let days: [DayCapacityForecastDay]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                ForecastDayMarker(day: day)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ForecastDayMarker: View {
    let day: DayCapacityForecastDay

    private var pressureColor: Color {
        switch day.status {
        case .comfortable:
            return .primary.opacity(0.24)
        case .tight:
            return .orange
        case .overloaded:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel)
                .font(.caption2.weight(isMeaningful ? .semibold : .medium))
                .foregroundStyle(isMeaningful ? pressureColor : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 18, height: 40)

                Capsule()
                    .fill(pressureColor)
                    .frame(width: 18, height: barHeight)
            }
            .frame(maxWidth: .infinity)

            Text(dayDueLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(day.dueOnDaySeconds > 0 ? .primary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isMeaningful: Bool {
        day.status != .comfortable
    }

    private var barHeight: CGFloat {
        let ratio = day.pressureRatio.isFinite ? min(max(day.pressureRatio, 0), 1) : 1
        return max(4, 40 * ratio)
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(day.planningWindow.labelDate) {
            return "Today"
        }
        return day.planningWindow.labelDate.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayDueLabel: String {
        if day.dueOnDaySeconds > 0 {
            return formatDuration(day.dueOnDaySeconds)
        }
        return " "
    }

    private var accessibilityLabel: String {
        let fullDate = day.planningWindow.labelDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let dueText = day.dueOnDaySeconds > 0 ? "\(formatDuration(day.dueOnDaySeconds)) due" : "no estimated work due"
        let unknownText = day.unknownDurationCount > 0 ? ", \(day.unknownDurationCount) unknown duration\(day.unknownDurationCount == 1 ? "" : "s")" : ""
        let pressureText = day.pressureRatio.isFinite ? "\(pressurePercent) pressure" : "pressure unknown"
        return "\(fullDate), \(statusLabel), \(dueText)\(unknownText), \(formatDuration(day.availableSecondsForDeadlines)) free, \(pressureText)"
    }

    private var statusLabel: String {
        switch day.status {
        case .comfortable:
            return "Comfortable"
        case .tight:
            return "Tight"
        case .overloaded:
            return "Overloaded"
        }
    }

    private var pressurePercent: String {
        guard day.pressureRatio.isFinite else { return "—" }
        return "\(Int((day.pressureRatio * 100).rounded()))%"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct ForecastCohortDetailRow: View {
    let cohort: DayCapacityForecastCohort

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(projectColor)
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cohort.project.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(workloadText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text("Due \(shortDate(cohort.deadlineDate))")
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(beginByText)
                        .foregroundStyle(beginByColor)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var projectColor: Color {
        guard let themeColor = cohort.project.themeColor else { return .secondary }
        return Color(hex: themeColor) ?? .secondary
    }

    private var workloadText: String {
        let duration = formatDuration(cohort.workloadSeconds)
        if cohort.unknownDurationCount > 0 {
            return cohort.workloadSeconds > 0 ? "\(duration) +?" : "?"
        }
        return duration
    }

    private var beginByText: String {
        if let latestSafeStartDate = cohort.latestSafeStartDate {
            return "Begin \(shortDate(latestSafeStartDate))"
        }
        if cohort.isInsufficientCapacity {
            return "No safe start"
        }
        return "Begin-by unknown"
    }

    private var beginByColor: Color {
        cohort.isInsufficientCapacity ? .red : .secondary
    }

    private func shortDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
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

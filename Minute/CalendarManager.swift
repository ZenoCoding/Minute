//
//  CalendarManager.swift
//  Minute
//
//  Manages integration with EventKit (Apple Calendar).
//

import Foundation
import EventKit
import SwiftUI
import Combine
import AppKit

enum CalendarVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case highlight
    case contextOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .highlight:
            return "Highlight"
        case .contextOnly:
            return "Context Only"
        }
    }
}

enum CalendarHighlightKind: String, Codable {
    case normal
    case specialDay
}

struct CalendarHighlight: Identifiable {
    let id: String
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let kind: CalendarHighlightKind
    let calendarColor: NSColor

    init(event: EKEvent, kind: CalendarHighlightKind) {
        let identifier = event.calendarItemIdentifier
        let rawTitle = event.title ?? ""
        self.id = "\(identifier)-\(kind.rawValue)"
        self.eventIdentifier = identifier
        self.title = rawTitle.isEmpty ? "Untitled Event" : rawTitle
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.kind = kind
        self.calendarColor = event.calendar.color
    }
}

@MainActor
class CalendarManager: ObservableObject {
    static let includeSpecialDaysKey = "calendar_highlight_include_special_days"
    static let includeRecurringMeetingsKey = "calendar_highlight_include_recurring_meetings"
    static let calendarVisibilityModePrefix = "calendar_visibility_mode_"
    private static let refreshIntervalSeconds: TimeInterval = 300

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var refreshTimer: AnyCancellable?
    private var storeChangeObserver: AnyCancellable?
    private var appActiveObserver: AnyCancellable?
    private var lastFetchDate: Date?
    @Published var events: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    var canReadEvents: Bool {
        authorizationStatus == .fullAccess
    }

    var canWriteEvents: Bool {
        authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configureObservers()
        checkStatus()
    }
    
    deinit {
        refreshTimer?.cancel()
        storeChangeObserver?.cancel()
        appActiveObserver?.cancel()
    }
    
    func checkStatus(fetchIfReadable: Bool = true) {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if canReadEvents {
            guard fetchIfReadable else { return }
            fetchEvents()
        } else if !events.isEmpty {
            events = []
        }
    }
    
    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.checkStatus()
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.checkStatus()
                }
            }
        }
    }

    @discardableResult
    func createQuickEvent(
        title: String,
        date: Date?,
        duration: TimeInterval?,
        hasExplicitTime: Bool
    ) -> Bool {
        checkStatus(fetchIfReadable: false)
        guard canWriteEvents else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let writableCalendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        guard let targetCalendar = store.defaultCalendarForNewEvents ?? writableCalendars.first else {
            return false
        }

        let calendar = Calendar.current
        let anchorDate = date ?? Date()
        let event = EKEvent(eventStore: store)
        event.title = trimmedTitle
        event.calendar = targetCalendar

        if hasExplicitTime {
            let eventDuration = max(60, duration ?? 3600)
            event.startDate = anchorDate
            event.endDate = anchorDate.addingTimeInterval(eventDuration)
            event.isAllDay = false
        } else {
            let startOfDay = calendar.startOfDay(for: anchorDate)
            let daySpan: Int = {
                guard let duration else { return 1 }
                return max(1, Int(ceil(duration / 86_400)))
            }()
            let endOfEvent = calendar.date(byAdding: .day, value: daySpan, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
            event.startDate = startOfDay
            event.endDate = endOfEvent
            event.isAllDay = true
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
            if canReadEvents {
                fetchEvents(anchorDate: Date())
            }
            return true
        } catch {
            print("Failed to save event: \(error)")
            return false
        }
    }
    
    func fetchEvents(anchorDate: Date = Date()) {
        guard canReadEvents else {
            events = []
            return
        }

        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else {
            events = []
            lastFetchDate = anchorDate
            return
        }
        
        // Keep a 4-day rolling window (yesterday + today + tomorrow + next day)
        // so UI transitions around midnight do not drop upcoming events.
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: anchorDate)
        let rangeStart = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let rangeEnd = calendar.date(byAdding: .day, value: 3, to: startOfDay) ?? startOfDay
        
        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: calendars)
        
        let fetchedEvents = store.events(matching: predicate)
        self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
        self.lastFetchDate = anchorDate
    }
    
    // Helper to group events by day or interleave
    func events(for date: Date) -> [EKEvent] {
        return events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }

    func todayEvents(for date: Date, now: Date) -> [EKEvent] {
        events(on: date, now: now, includePast: false)
    }

    func tomorrowEvents(from date: Date, now: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return events(on: tomorrow, now: now, includePast: true)
    }

    func events(on date: Date, now: Date, includePast: Bool) -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return events
            .filter { event in
                event.startDate < endOfDay &&
                event.endDate > startOfDay &&
                (includePast || !calendar.isDateInToday(date) || event.endDate > now)
            }
            .sorted(by: sortEventsByDayOrder)
    }

    func nextEvent(after now: Date) -> EKEvent? {
        let upcoming = events.filter { $0.endDate > now }
        let upcomingTimed = upcoming.filter { !$0.isAllDay }

        if let nextTimed = upcomingTimed.sorted(by: sortEventsByDayOrder).first {
            return nextTimed
        }

        return upcoming.sorted(by: sortEventsByDayOrder).first
    }

    func busySeconds(on date: Date, now: Date) -> TimeInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let lowerBound = calendar.isDateInToday(date) ? max(now, startOfDay) : startOfDay
        guard endOfDay > lowerBound else { return 0 }

        let dayRange = DateInterval(start: lowerBound, end: endOfDay)
        let clipped = events(on: date, now: now, includePast: false).compactMap { event -> DateInterval? in
            let start = max(event.startDate, dayRange.start)
            let end = min(event.endDate, dayRange.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }

        return mergeIntervals(clipped).reduce(0) { $0 + $1.duration }
    }

    func highlights(for date: Date, now: Date) -> [CalendarHighlight] {
        let includeSpecialDays = boolSetting(Self.includeSpecialDaysKey, default: true)
        let includeRecurringMeetings = boolSetting(Self.includeRecurringMeetingsKey, default: true)

        let classified = todayEvents(for: date, now: now).compactMap { event -> CalendarHighlight? in
            switch disposition(for: event, includeSpecialDays: includeSpecialDays, includeRecurringMeetings: includeRecurringMeetings) {
            case .normal:
                return CalendarHighlight(event: event, kind: .normal)
            case .specialDay:
                return CalendarHighlight(event: event, kind: .specialDay)
            case .contextOnly:
                return nil
            }
        }

        var normals = classified.filter { $0.kind == .normal }
        var specials = classified.filter { $0.kind == .specialDay }

        var selected = Array(normals.prefix(2))
        selected.append(contentsOf: specials.prefix(2))

        normals.removeFirst(min(2, normals.count))
        specials.removeFirst(min(2, specials.count))

        while selected.count < 4 {
            if let nextNormal = normals.first {
                selected.append(nextNormal)
                normals.removeFirst()
            } else if let nextSpecial = specials.first {
                selected.append(nextSpecial)
                specials.removeFirst()
            } else {
                break
            }
        }

        return selected
    }

    func availableCalendars() -> [EKCalendar] {
        guard authorizationStatus == .fullAccess || authorizationStatus == .writeOnly else {
            return []
        }

        return store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func visibilityMode(for calendar: EKCalendar) -> CalendarVisibilityMode {
        visibilityMode(for: calendar.calendarIdentifier)
    }

    func visibilityMode(for calendarIdentifier: String) -> CalendarVisibilityMode {
        let key = visibilityModeKey(for: calendarIdentifier)
        guard let rawValue = defaults.string(forKey: key),
              let mode = CalendarVisibilityMode(rawValue: rawValue) else {
            return .auto
        }
        return mode
    }

    func setVisibilityMode(_ mode: CalendarVisibilityMode, for calendarIdentifier: String) {
        let key = visibilityModeKey(for: calendarIdentifier)
        defaults.set(mode.rawValue, forKey: key)
        objectWillChange.send()
    }

    /// Returns merged busy intervals from loaded events clipped to the provided range.
    func busyIntervals(in range: DateInterval) -> [DateInterval] {
        guard range.duration > 0 else { return [] }

        let clipped = events.compactMap { event -> DateInterval? in
            let start = max(event.startDate, range.start)
            let end = min(event.endDate, range.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }

        return mergeIntervals(clipped)
    }

    private func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }

        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    private func sortEventsByDayOrder(_ lhs: EKEvent, _ rhs: EKEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }

        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        if lhs.endDate != rhs.endDate {
            return lhs.endDate < rhs.endDate
        }

        let lhsTitle = lhs.title ?? ""
        let rhsTitle = rhs.title ?? ""
        return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
    }

    private enum HighlightDisposition {
        case normal
        case specialDay
        case contextOnly
    }

    private func disposition(for event: EKEvent, includeSpecialDays: Bool, includeRecurringMeetings: Bool) -> HighlightDisposition {
        switch visibilityMode(for: event.calendar.calendarIdentifier) {
        case .contextOnly:
            return .contextOnly
        case .highlight:
            if includeSpecialDays && event.isAllDay && isSpecialDayEvent(event) {
                return .specialDay
            }
            return .normal
        case .auto:
            break
        }

        if event.isAllDay {
            if includeSpecialDays && isSpecialDayEvent(event) {
                return .specialDay
            }
            return .contextOnly
        }

        if isSchoolLikeRecurring(event) {
            return .contextOnly
        }

        if event.recurrenceRules?.isEmpty == false {
            if includeRecurringMeetings && isMeetingLike(event) {
                return .normal
            }
            return .contextOnly
        }

        return .normal
    }

    private func isSpecialDayEvent(_ event: EKEvent) -> Bool {
        let specialKeywords = [
            "birthday", "birthdays", "holiday", "anniversary", "vacation", "day off", "valentine"
        ]
        let calendarKeywords = [
            "birthday", "birthdays", "holiday", "holidays", "special days"
        ]

        return containsAnyKeyword(in: event.title, keywords: specialKeywords) ||
               containsAnyKeyword(in: event.calendar.title, keywords: calendarKeywords)
    }

    private func isMeetingLike(_ event: EKEvent) -> Bool {
        let meetingKeywords = [
            "meeting", "sync", "standup", "1:1", "review", "planning",
            "retro", "interview", "check-in", "panel"
        ]
        if containsAnyKeyword(in: event.title, keywords: meetingKeywords) {
            return true
        }
        return (event.attendees?.isEmpty == false)
    }

    private func isSchoolLikeRecurring(_ event: EKEvent) -> Bool {
        guard let recurrenceRule = event.recurrenceRules?.first else { return false }

        let classKeywords = [
            "class", "period", "lecture", "lab", "homeroom", "study hall"
        ]
        let calendarKeywords = [
            "school", "class", "classes", "timetable", "schedule"
        ]

        if containsAnyKeyword(in: event.title, keywords: classKeywords) ||
            containsAnyKeyword(in: event.calendar.title, keywords: calendarKeywords) {
            return true
        }

        let duration = event.endDate.timeIntervalSince(event.startDate)
        switch recurrenceRule.frequency {
        case .daily:
            return duration <= 90 * 60
        case .weekly:
            let dayCount = recurrenceRule.daysOfTheWeek?.count ?? 0
            return dayCount >= 3 && duration <= 90 * 60
        default:
            return false
        }
    }

    private func containsAnyKeyword(in source: String?, keywords: [String]) -> Bool {
        guard let source else { return false }
        let normalized = source.lowercased()
        return keywords.contains { normalized.contains($0) }
    }

    private func boolSetting(_ key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func visibilityModeKey(for calendarIdentifier: String) -> String {
        "\(Self.calendarVisibilityModePrefix)\(calendarIdentifier)"
    }

    private func configureObservers() {
        refreshTimer = Timer.publish(every: Self.refreshIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.refreshIfNeeded(force: false, now: date)
            }

        storeChangeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                self?.refreshIfNeeded(force: true, now: Date())
            }

        appActiveObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshIfNeeded(force: true, now: Date())
            }
    }

    private func refreshIfNeeded(force: Bool, now: Date) {
        checkStatus(fetchIfReadable: false)
        guard canReadEvents else { return }

        if force || shouldRefresh(for: now) {
            fetchEvents(anchorDate: now)
        }
    }

    private func shouldRefresh(for now: Date) -> Bool {
        guard let lastFetchDate else { return true }
        let calendar = Calendar.current
        if !calendar.isDate(lastFetchDate, inSameDayAs: now) {
            return true
        }
        return now.timeIntervalSince(lastFetchDate) >= Self.refreshIntervalSeconds
    }
}

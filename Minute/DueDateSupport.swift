//
//  DueDateSupport.swift
//  Minute
//
//  Shared helpers for task due-date presets and day-only normalization.
//

import Foundation

enum DueDateSupport {
    private static let secondsPerDay: TimeInterval = 86_400

    static func presetToday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    static func presetTomorrow(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(secondsPerDay)
    }

    static func presetNextSaturday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let nextSaturday = calendar.nextDate(
            after: now,
            matching: DateComponents(weekday: 7),
            matchingPolicy: .nextTime
        ) ?? now
        return calendar.startOfDay(for: nextSaturday)
    }

    static func normalizeParsedDate(_ date: Date?, hasExplicitTime: Bool, calendar: Calendar = .current) -> Date? {
        guard let date else { return nil }
        guard !hasExplicitTime else { return date }
        return calendar.startOfDay(for: date)
    }
}

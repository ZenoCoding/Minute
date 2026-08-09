//
//  DueDateSupport.swift
//  Minute
//
//  Shared helpers for task due-date presets and day-only normalization.
//

import Foundation

enum DueDateSupport {
    static func presetToday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    static func presetTomorrow(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    static func presetNextSaturday(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        let offset = daysUntilSaturday == 0 ? 7 : daysUntilSaturday
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func normalizeParsedDate(_ date: Date?, hasExplicitTime: Bool, calendar: Calendar = .current) -> Date? {
        guard let date else { return nil }
        guard !hasExplicitTime else { return date }
        return calendar.startOfDay(for: date)
    }

    /// Returns the target day while retaining a timed deadline's wall-clock time.
    /// A day-only deadline remains exactly day-only; this deliberately avoids
    /// adding 24-hour intervals so daylight-saving transitions do not shift the
    /// displayed time.
    static func rescheduledDate(
        from originalDate: Date?,
        to targetDay: Date,
        calendar: Calendar = .current
    ) -> Date {
        let targetStart = calendar.startOfDay(for: targetDay)
        guard let originalDate, !isDayOnly(originalDate, calendar: calendar) else {
            return targetStart
        }

        var components = calendar.dateComponents([.year, .month, .day], from: targetStart)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: originalDate)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? targetStart
    }

    static func isDayOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) == 0 &&
        calendar.component(.minute, from: date) == 0 &&
        calendar.component(.second, from: date) == 0 &&
        calendar.component(.nanosecond, from: date) == 0
    }
}

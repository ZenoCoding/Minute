//
//  DayCapacityService.swift
//  Minute
//
//  Computes sleep-aware planning windows, capacity, and overload deferral suggestions.
//

import Foundation

enum DayCapacitySettings {
    static let useFallbackDurationKey = "day_capacity_use_fallback_duration"
    static let fallbackDurationMinutesKey = "day_capacity_fallback_duration_minutes"
    static let defaultFallbackDurationMinutes = 30

    static let sleepWeekdayWakeMinutesKey = "day_capacity_sleep_weekday_wake_minutes"
    static let sleepWeekdayBedMinutesKey = "day_capacity_sleep_weekday_bed_minutes"
    static let sleepWeekendWakeMinutesKey = "day_capacity_sleep_weekend_wake_minutes"
    static let sleepWeekendBedMinutesKey = "day_capacity_sleep_weekend_bed_minutes"

    static let defaultSleepWeekdayWakeMinutes = 7 * 60
    static let defaultSleepWeekdayBedMinutes = 22 * 60 + 30
    static let defaultSleepWeekendWakeMinutes = 8 * 60
    static let defaultSleepWeekendBedMinutes = 23 * 60
}

struct SleepSchedule {
    let weekdayWakeMinutes: Int
    let weekdayBedMinutes: Int
    let weekendWakeMinutes: Int
    let weekendBedMinutes: Int

    func wakeAndBedMinutes(for date: Date, calendar: Calendar) -> (wake: Int, bed: Int) {
        if calendar.isDateInWeekend(date) {
            return (clampMinutes(weekendWakeMinutes), clampMinutes(weekendBedMinutes))
        }
        return (clampMinutes(weekdayWakeMinutes), clampMinutes(weekdayBedMinutes))
    }

    private func clampMinutes(_ value: Int) -> Int {
        min(max(value, 0), 1439)
    }
}

struct PlanningDayWindow {
    let start: Date
    let end: Date
    let labelDate: Date
    let isOffHours: Bool

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct SleepAwareDayClassifier {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func planningWindow(for now: Date, schedule: SleepSchedule) -> PlanningDayWindow {
        let today = calendar.startOfDay(for: now)
        guard
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        else {
            return planningWindow(labelDate: today, schedule: schedule, isOffHours: false)
        }

        let previousWindow = planningWindow(labelDate: yesterday, schedule: schedule, isOffHours: false)
        if now >= previousWindow.start && now < previousWindow.end {
            return previousWindow
        }

        let currentWindow = planningWindow(labelDate: today, schedule: schedule, isOffHours: false)
        if now >= currentWindow.start && now < currentWindow.end {
            return currentWindow
        }

        let nextWindow = planningWindow(labelDate: tomorrow, schedule: schedule, isOffHours: false)
        let upcoming = [currentWindow, nextWindow].filter { $0.start > now }.min { $0.start < $1.start } ?? nextWindow

        return PlanningDayWindow(
            start: upcoming.start,
            end: upcoming.end,
            labelDate: upcoming.labelDate,
            isOffHours: true
        )
    }

    func planningWindow(after window: PlanningDayWindow, offset: Int, schedule: SleepSchedule) -> PlanningDayWindow {
        let clampedOffset = max(offset, 0)
        let baseLabelDate = calendar.startOfDay(for: window.labelDate)
        let targetLabelDate = calendar.date(byAdding: .day, value: clampedOffset, to: baseLabelDate) ?? baseLabelDate
        return planningWindow(labelDate: targetLabelDate, schedule: schedule, isOffHours: false)
    }

    private func planningWindow(labelDate: Date, schedule: SleepSchedule, isOffHours: Bool) -> PlanningDayWindow {
        let dayStart = calendar.startOfDay(for: labelDate)
        let scheduleForDay = schedule.wakeAndBedMinutes(for: dayStart, calendar: calendar)

        let start = calendar.date(byAdding: .minute, value: scheduleForDay.wake, to: dayStart) ?? dayStart
        let endBase = scheduleForDay.bed <= scheduleForDay.wake
            ? (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart)
            : dayStart
        let end = calendar.date(byAdding: .minute, value: scheduleForDay.bed, to: endBase) ?? endBase

        return PlanningDayWindow(start: start, end: end, labelDate: dayStart, isOffHours: isOffHours)
    }
}

struct DayCapacitySnapshot {
    enum Status {
        case onTrack
        case nearCapacity
        case overloaded
    }

    let availableSecondsToday: TimeInterval
    let requiredSecondsToday: TimeInterval
    let unknownTaskCount: Int

    var overloadSeconds: TimeInterval {
        max(0, requiredSecondsToday - availableSecondsToday)
    }

    var utilization: Double {
        guard availableSecondsToday > 0 else {
            return requiredSecondsToday > 0 ? 1.0 : 0.0
        }
        return min(requiredSecondsToday / availableSecondsToday, 1.0)
    }

    var status: Status {
        if overloadSeconds > 0 {
            return .overloaded
        }

        guard availableSecondsToday > 0 else {
            return requiredSecondsToday > 0 ? .overloaded : .onTrack
        }

        return (requiredSecondsToday / availableSecondsToday) >= 0.85 ? .nearCapacity : .onTrack
    }
}

struct DayCapacityDeferralSuggestion {
    let taskIDs: [UUID]
    let taskCount: Int
    let deferredSeconds: TimeInterval
}

struct DayCapacityService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func snapshot(
        now: Date,
        planningWindow: PlanningDayWindow,
        tasks: [TaskItem],
        busyIntervals: [DateInterval],
        useFallbackDuration: Bool,
        fallbackDurationMinutes: Int
    ) -> DayCapacitySnapshot {
        let availableSeconds = availableSeconds(now: now, planningWindow: planningWindow, busyIntervals: busyIntervals)
        let requiredTasks = tasks.filter { task in
            guard !task.isCompleted else { return false }
            guard let dueDate = task.dueDate else { return false }
            return dueDate < planningWindow.end
        }

        let fallbackSeconds = TimeInterval(max(1, fallbackDurationMinutes) * 60)
        var requiredSeconds: TimeInterval = 0
        var unknownCount = 0

        for task in requiredTasks {
            if let duration = normalizedDuration(task.estimatedDuration) {
                requiredSeconds += duration
            } else {
                unknownCount += 1
                if useFallbackDuration {
                    requiredSeconds += fallbackSeconds
                }
            }
        }

        return DayCapacitySnapshot(
            availableSecondsToday: availableSeconds,
            requiredSecondsToday: requiredSeconds,
            unknownTaskCount: unknownCount
        )
    }

    func suggestedDeferrals(
        planningWindow: PlanningDayWindow,
        tasks: [TaskItem],
        overloadSeconds: TimeInterval,
        useFallbackDuration: Bool,
        fallbackDurationMinutes: Int
    ) -> DayCapacityDeferralSuggestion? {
        guard overloadSeconds > 0 else { return nil }

        let fallbackSeconds = TimeInterval(max(1, fallbackDurationMinutes) * 60)

        let candidates: [(task: TaskItem, dueDate: Date, duration: TimeInterval, noSpecificTime: Bool)] = tasks.compactMap { task in
            guard !task.isCompleted else { return nil }
            guard !task.isRecurring else { return nil }
            guard let dueDate = task.dueDate else { return nil }
            guard dueDate >= planningWindow.start && dueDate < planningWindow.end else { return nil }

            let duration: TimeInterval
            if let explicitDuration = normalizedDuration(task.estimatedDuration) {
                duration = explicitDuration
            } else if useFallbackDuration {
                duration = fallbackSeconds
            } else {
                return nil
            }

            return (
                task: task,
                dueDate: dueDate,
                duration: duration,
                noSpecificTime: !hasSpecificTime(dueDate)
            )
        }

        guard !candidates.isEmpty else { return nil }

        let ranked = candidates.sorted { lhs, rhs in
            if lhs.noSpecificTime != rhs.noSpecificTime {
                return lhs.noSpecificTime && !rhs.noSpecificTime
            }

            if lhs.dueDate != rhs.dueDate {
                return lhs.dueDate > rhs.dueDate
            }

            if lhs.duration != rhs.duration {
                return lhs.duration > rhs.duration
            }

            return lhs.task.orderIndex > rhs.task.orderIndex
        }

        var selectedTaskIDs: [UUID] = []
        var coveredSeconds: TimeInterval = 0

        for candidate in ranked {
            selectedTaskIDs.append(candidate.task.id)
            coveredSeconds += candidate.duration
            if coveredSeconds >= overloadSeconds {
                break
            }
        }

        guard !selectedTaskIDs.isEmpty else { return nil }

        return DayCapacityDeferralSuggestion(
            taskIDs: selectedTaskIDs,
            taskCount: selectedTaskIDs.count,
            deferredSeconds: coveredSeconds
        )
    }

    func deferredDateToNextPlanningDay(from dueDate: Date?, nextPlanningWindow: PlanningDayWindow) -> Date {
        let baseline = nextPlanningWindow.start
        guard let dueDate else { return baseline }
        guard hasSpecificTime(dueDate) else { return baseline }

        let components = calendar.dateComponents([.hour, .minute, .second], from: dueDate)
        let dayStart = calendar.startOfDay(for: nextPlanningWindow.labelDate)
        let candidate = calendar.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: dayStart
        ) ?? baseline

        if candidate >= nextPlanningWindow.start && candidate < nextPlanningWindow.end {
            return candidate
        }

        return baseline
    }

    private func availableSeconds(now: Date, planningWindow: PlanningDayWindow, busyIntervals: [DateInterval]) -> TimeInterval {
        let rangeStart = planningWindow.isOffHours ? planningWindow.start : max(now, planningWindow.start)
        guard planningWindow.end > rangeStart else { return 0 }

        let totalRemaining = planningWindow.end.timeIntervalSince(rangeStart)
        let remainingRange = DateInterval(start: rangeStart, end: planningWindow.end)

        let busySeconds = busyIntervals.reduce(0) { sum, interval in
            let start = max(interval.start, remainingRange.start)
            let end = min(interval.end, remainingRange.end)
            guard end > start else { return sum }
            return sum + end.timeIntervalSince(start)
        }

        return max(0, totalRemaining - busySeconds)
    }

    private func normalizedDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func hasSpecificTime(_ date: Date) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }
}

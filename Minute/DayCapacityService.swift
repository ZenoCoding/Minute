//
//  DayCapacityService.swift
//  Minute
//
//  Computes sleep-aware planning windows, capacity, and deadline pressure.
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

    var spareSeconds: TimeInterval {
        max(0, availableSecondsToday - requiredSecondsToday)
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

struct DayCapacityPullForwardSuggestion {
    let taskIDs: [UUID]
    let taskCount: Int
    let pulledForwardSeconds: TimeInterval
}

struct DayCapacityForecastProject: Hashable {
    let id: UUID?
    let name: String
    let themeColor: String?

    init(id: UUID? = nil, name: String, themeColor: String? = nil) {
        self.id = id
        self.name = name
        self.themeColor = themeColor
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unassigned" : name
    }
}

/// A value-only task projection used by the forecast calculation and its tests.
/// It deliberately contains no mutation hooks or task ordering information.
struct DayCapacityForecastTask {
    let id: UUID
    let dueDate: Date
    let estimatedDuration: TimeInterval?
    let project: DayCapacityForecastProject

    init(
        id: UUID = UUID(),
        dueDate: Date,
        estimatedDuration: TimeInterval?,
        project: DayCapacityForecastProject
    ) {
        self.id = id
        self.dueDate = dueDate
        self.estimatedDuration = estimatedDuration
        self.project = project
    }
}

struct DayCapacityForecastDayInput {
    let window: PlanningDayWindow
    let busyIntervals: [DateInterval]

    init(window: PlanningDayWindow, busyIntervals: [DateInterval] = []) {
        self.window = window
        self.busyIntervals = busyIntervals
    }
}

struct DayCapacityForecastProjectWorkload: Identifiable {
    let project: DayCapacityForecastProject
    let dueSeconds: TimeInterval
    let taskCount: Int
    let unknownDurationCount: Int

    var id: String {
        "\(project.id?.uuidString ?? "name:\(project.displayName)")"
    }
}

struct DayCapacityForecastCohort: Identifiable {
    let project: DayCapacityForecastProject
    let deadlineDate: Date
    let workloadSeconds: TimeInterval
    let unknownDurationCount: Int
    let latestSafeStartDate: Date?
    let isInsufficientCapacity: Bool

    var id: String {
        "\(project.id?.uuidString ?? "name:\(project.displayName)")|\(deadlineDate.timeIntervalSinceReferenceDate)"
    }

    var usesFallbackEstimate: Bool {
        unknownDurationCount > 0
    }
}

struct DayCapacityForecastDay: Identifiable {
    enum PressureStatus: String, Equatable {
        case comfortable
        case tight
        case overloaded
    }

    let planningWindow: PlanningDayWindow
    let availableSeconds: TimeInterval
    let availableSecondsForDeadlines: TimeInterval
    let dueOnDaySeconds: TimeInterval
    let cumulativeDueSeconds: TimeInterval
    let cumulativeCapacitySeconds: TimeInterval
    let pressureRatio: Double
    let unknownDurationCount: Int
    let status: PressureStatus
    let projectWorkloads: [DayCapacityForecastProjectWorkload]

    var id: Date {
        planningWindow.labelDate
    }

    var hasWorkDue: Bool {
        dueOnDaySeconds > 0 || unknownDurationCount > 0
    }
}

struct DayCapacityForecast {
    let days: [DayCapacityForecastDay]
    let cohorts: [DayCapacityForecastCohort]
    let usesFallbackDuration: Bool

    var hasDatedTasks: Bool {
        !cohorts.isEmpty
    }

    var unknownDurationCount: Int {
        days.reduce(0) { $0 + $1.unknownDurationCount }
    }

    var hasUnknownDurations: Bool {
        unknownDurationCount > 0
    }
}

struct DayCapacityService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Builds the read-only projection from the SwiftData model. The forecast
    /// only includes incomplete tasks with an active project and a deadline.
    func forecast(
        now: Date,
        tasks: [TaskItem],
        dayInputs: [DayCapacityForecastDayInput],
        useFallbackDuration: Bool,
        fallbackDurationMinutes: Int
    ) -> DayCapacityForecast {
        let forecastTasks = tasks.compactMap { task -> DayCapacityForecastTask? in
            guard !task.isCompleted, let dueDate = task.dueDate else {
                return nil
            }

            if let project = task.project, project.status != .active {
                return nil
            }

            let project = task.project.map {
                DayCapacityForecastProject(
                    id: $0.id,
                    name: $0.name,
                    themeColor: $0.area?.themeColor
                )
            } ?? DayCapacityForecastProject(name: "Unassigned")

            return DayCapacityForecastTask(
                id: task.id,
                dueDate: dueDate,
                estimatedDuration: task.estimatedDuration,
                project: project
            )
        }

        return calculate(
            now: now,
            tasks: forecastTasks,
            dayInputs: dayInputs,
            useFallbackDuration: useFallbackDuration,
            fallbackDurationMinutes: fallbackDurationMinutes
        )
    }

    /// Pure seven-day deadline pressure calculation. It never returns a task
    /// mutation or a task ranking; all begin-by data is cohort-level.
    func calculate(
        now: Date,
        tasks: [DayCapacityForecastTask],
        dayInputs: [DayCapacityForecastDayInput],
        useFallbackDuration: Bool,
        fallbackDurationMinutes: Int
    ) -> DayCapacityForecast {
        let inputs = Array(dayInputs.prefix(7))
        guard !inputs.isEmpty else {
            return DayCapacityForecast(days: [], cohorts: [], usesFallbackDuration: useFallbackDuration)
        }

        let fallbackSeconds = TimeInterval(max(1, fallbackDurationMinutes) * 60)
        let availableByDay = inputs.enumerated().map { index, input in
            availableSeconds(
                for: input,
                start: index == 0 ? max(input.window.start, now) : input.window.start,
                end: input.window.end
            )
        }
        let firstLabelDate = calendar.startOfDay(for: inputs[0].window.labelDate)

        let resolvedTasks: [ResolvedForecastTask] = tasks.compactMap { task in
            guard let dayIndex = forecastDayIndex(for: task.dueDate, firstLabelDate: firstLabelDate, inputs: inputs, now: now) else {
                return nil
            }

            let isUnknown = normalizedDuration(task.estimatedDuration) == nil
            let duration = normalizedDuration(task.estimatedDuration) ?? (useFallbackDuration ? fallbackSeconds : 0)
            let isOverdue = isOverdue(task.dueDate, firstLabelDate: firstLabelDate, now: now)

            return ResolvedForecastTask(
                task: task,
                dayIndex: dayIndex,
                duration: duration,
                isUnknown: isUnknown,
                isOverdue: isOverdue
            )
        }

        var cumulativeDueSeconds: TimeInterval = 0
        var cumulativeCapacitySeconds: TimeInterval = 0
        var outputDays: [DayCapacityForecastDay] = []

        for dayIndex in inputs.indices {
            let dayTasks = resolvedTasks.filter { $0.dayIndex == dayIndex }
            let dayDueSeconds = dayTasks.reduce(0) { $0 + $1.duration }
            let dayUnknownCount = dayTasks.filter(\.isUnknown).count
            cumulativeDueSeconds += dayDueSeconds
            cumulativeCapacitySeconds += availableByDay[dayIndex]

            let endOfDayRatio = pressureRatio(
                dueSeconds: cumulativeDueSeconds,
                capacitySeconds: cumulativeCapacitySeconds
            )
            let timedDeadlineRatios = dayTasks
                .filter { hasSpecificTime($0.task.dueDate) && !$0.isOverdue }
                .map { task in
                    let dueByDeadline = resolvedTasks.reduce(0) { sum, candidate in
                        guard candidate.dayIndex < dayIndex ||
                                (candidate.dayIndex == dayIndex && candidate.task.dueDate <= task.task.dueDate) else {
                            return sum
                        }
                        return sum + candidate.duration
                    }
                    let capacityByDeadline = cumulativeCapacityBeforeDay(
                        dayIndex: dayIndex,
                        deadline: task.task.dueDate,
                        inputs: inputs,
                        availableByDay: availableByDay,
                        now: now
                    )
                    return pressureRatio(dueSeconds: dueByDeadline, capacitySeconds: capacityByDeadline)
                }
            let dayPressureRatio = max(endOfDayRatio, timedDeadlineRatios.max() ?? 0)

            let latestDeadline = dayTasks.map { task -> Date in
                if task.isOverdue || !hasSpecificTime(task.task.dueDate) {
                    return inputs[dayIndex].window.end
                }
                return min(task.task.dueDate, inputs[dayIndex].window.end)
            }.max()
            let availableForDeadlines: TimeInterval
            if let latestDeadline {
                availableForDeadlines = availableSeconds(
                    for: inputs[dayIndex],
                    start: dayIndex == 0 ? max(inputs[dayIndex].window.start, now) : inputs[dayIndex].window.start,
                    end: latestDeadline
                )
            } else {
                availableForDeadlines = availableByDay[dayIndex]
            }

            outputDays.append(
                DayCapacityForecastDay(
                    planningWindow: inputs[dayIndex].window,
                    availableSeconds: availableByDay[dayIndex],
                    availableSecondsForDeadlines: availableForDeadlines,
                    dueOnDaySeconds: dayDueSeconds,
                    cumulativeDueSeconds: cumulativeDueSeconds,
                    cumulativeCapacitySeconds: cumulativeCapacitySeconds,
                    pressureRatio: dayPressureRatio,
                    unknownDurationCount: dayUnknownCount,
                    status: pressureStatus(for: dayPressureRatio),
                    projectWorkloads: projectWorkloads(for: dayTasks)
                )
            )
        }

        let cohortAccumulators = makeCohortAccumulators(
            from: resolvedTasks,
            inputs: inputs
        )
        let cohorts = cohortAccumulators.map { cohort in
            let cumulativeWorkThroughDeadline = resolvedTasks.reduce(0) { sum, task in
                let taskDeadline = effectiveForecastDeadline(for: task, inputs: inputs)
                guard task.dayIndex < cohort.dayIndex ||
                        (task.dayIndex == cohort.dayIndex && taskDeadline <= cohort.deadlineDate) else {
                    return sum
                }
                return sum + task.duration
            }
            let beginBy = beginByDate(
                workloadSeconds: cumulativeWorkThroughDeadline,
                dayIndex: cohort.dayIndex,
                deadline: cohort.deadlineDate,
                inputs: inputs,
                availableByDay: availableByDay,
                now: now
            )

            return DayCapacityForecastCohort(
                project: cohort.project,
                deadlineDate: cohort.deadlineDate,
                workloadSeconds: cohort.workloadSeconds,
                unknownDurationCount: cohort.unknownDurationCount,
                latestSafeStartDate: beginBy.latestSafeStartDate,
                isInsufficientCapacity: beginBy.isInsufficientCapacity
            )
        }

        return DayCapacityForecast(
            days: outputDays,
            cohorts: cohorts,
            usesFallbackDuration: useFallbackDuration
        )
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

    func suggestedPullForward(
        planningWindow: PlanningDayWindow,
        tasks: [TaskItem],
        availableSpareSeconds: TimeInterval,
        lookAheadWindowEnd: Date,
        useFallbackDuration: Bool,
        fallbackDurationMinutes: Int
    ) -> DayCapacityPullForwardSuggestion? {
        guard availableSpareSeconds > 0 else { return nil }

        let fallbackSeconds = TimeInterval(max(1, fallbackDurationMinutes) * 60)

        let candidates: [(task: TaskItem, dueDate: Date?, duration: TimeInterval, noSpecificTime: Bool)] = tasks.compactMap { task in
            guard !task.isCompleted else { return nil }
            guard !task.isRecurring else { return nil }

            if let dueDate = task.dueDate {
                guard dueDate >= planningWindow.end && dueDate < lookAheadWindowEnd else { return nil }
            }

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
                dueDate: task.dueDate,
                duration: duration,
                noSpecificTime: task.dueDate.map { !hasSpecificTime($0) } ?? true
            )
        }

        guard !candidates.isEmpty else { return nil }

        let ranked = candidates.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
            case (nil, nil):
                break
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            }

            if lhs.noSpecificTime != rhs.noSpecificTime {
                return lhs.noSpecificTime && !rhs.noSpecificTime
            }

            if lhs.duration != rhs.duration {
                return lhs.duration < rhs.duration
            }

            return lhs.task.orderIndex < rhs.task.orderIndex
        }

        var selectedTaskIDs: [UUID] = []
        var coveredSeconds: TimeInterval = 0
        let overshootCap = max(availableSpareSeconds * 1.2, availableSpareSeconds + 15 * 60)

        for candidate in ranked {
            let nextCovered = coveredSeconds + candidate.duration
            if nextCovered <= availableSpareSeconds {
                selectedTaskIDs.append(candidate.task.id)
                coveredSeconds = nextCovered
                continue
            }

            // If nothing fits cleanly, allow one slight overshoot so the user still gets a useful action.
            if selectedTaskIDs.isEmpty && candidate.duration <= overshootCap {
                selectedTaskIDs.append(candidate.task.id)
                coveredSeconds = nextCovered
                break
            }

            continue
        }

        guard !selectedTaskIDs.isEmpty else { return nil }

        return DayCapacityPullForwardSuggestion(
            taskIDs: selectedTaskIDs,
            taskCount: selectedTaskIDs.count,
            pulledForwardSeconds: coveredSeconds
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

    func pulledDateToCurrentPlanningDay(
        from dueDate: Date?,
        currentPlanningWindow: PlanningDayWindow,
        now: Date
    ) -> Date {
        let baseline = max(now, currentPlanningWindow.start)
        guard let dueDate else { return baseline }
        guard hasSpecificTime(dueDate) else { return baseline }

        let components = calendar.dateComponents([.hour, .minute, .second], from: dueDate)
        let dayStart = calendar.startOfDay(for: currentPlanningWindow.labelDate)
        let candidate = calendar.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: dayStart
        ) ?? baseline

        if candidate >= baseline && candidate < currentPlanningWindow.end {
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

    private struct ResolvedForecastTask {
        let task: DayCapacityForecastTask
        let dayIndex: Int
        let duration: TimeInterval
        let isUnknown: Bool
        let isOverdue: Bool
    }

    private struct CohortAccumulator {
        let project: DayCapacityForecastProject
        let dayIndex: Int
        let deadlineDate: Date
        var workloadSeconds: TimeInterval
        var unknownDurationCount: Int
    }

    private struct BeginByResult {
        let latestSafeStartDate: Date?
        let isInsufficientCapacity: Bool
    }

    private func forecastDayIndex(
        for dueDate: Date,
        firstLabelDate: Date,
        inputs: [DayCapacityForecastDayInput],
        now: Date
    ) -> Int? {
        if isOverdue(dueDate, firstLabelDate: firstLabelDate, now: now) {
            return 0
        }

        return inputs.firstIndex { input in
            calendar.isDate(dueDate, inSameDayAs: input.window.labelDate)
        }
    }

    private func isOverdue(_ dueDate: Date, firstLabelDate: Date, now: Date) -> Bool {
        let dueDay = calendar.startOfDay(for: dueDate)
        guard dueDay >= firstLabelDate else { return true }
        return hasSpecificTime(dueDate) && dueDate < now
    }

    private func availableSeconds(
        for input: DayCapacityForecastDayInput,
        start: Date,
        end: Date
    ) -> TimeInterval {
        let rangeStart = max(start, input.window.start)
        let rangeEnd = min(end, input.window.end)
        guard rangeEnd > rangeStart else { return 0 }

        let range = DateInterval(start: rangeStart, end: rangeEnd)
        let mergedBusyIntervals = mergeIntervals(input.busyIntervals)
        let busySeconds = mergedBusyIntervals.reduce(0) { sum, interval in
            let clippedStart = max(interval.start, range.start)
            let clippedEnd = min(interval.end, range.end)
            guard clippedEnd > clippedStart else { return sum }
            return sum + clippedEnd.timeIntervalSince(clippedStart)
        }
        return max(0, range.duration - busySeconds)
    }

    private func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let valid = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard !valid.isEmpty else { return [] }

        var merged: [DateInterval] = [valid[0]]
        for interval in valid.dropFirst() {
            guard let last = merged.last else { continue }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private func cumulativeCapacityBeforeDay(
        dayIndex: Int,
        deadline: Date,
        inputs: [DayCapacityForecastDayInput],
        availableByDay: [TimeInterval],
        now: Date
    ) -> TimeInterval {
        let priorCapacity = availableByDay.prefix(dayIndex).reduce(0, +)
        let currentCapacity = availableSeconds(
            for: inputs[dayIndex],
            start: dayIndex == 0 ? max(inputs[dayIndex].window.start, now) : inputs[dayIndex].window.start,
            end: deadline
        )
        return priorCapacity + currentCapacity
    }

    private func projectWorkloads(for tasks: [ResolvedForecastTask]) -> [DayCapacityForecastProjectWorkload] {
        var grouped: [String: (project: DayCapacityForecastProject, seconds: TimeInterval, count: Int, unknowns: Int)] = [:]
        for task in tasks {
            let key = task.task.project.id?.uuidString ?? "name:\(task.task.project.displayName)"
            let existing = grouped[key]
            grouped[key] = (
                project: existing?.project ?? task.task.project,
                seconds: (existing?.seconds ?? 0) + task.duration,
                count: (existing?.count ?? 0) + 1,
                unknowns: (existing?.unknowns ?? 0) + (task.isUnknown ? 1 : 0)
            )
        }

        return grouped.values
            .map {
                DayCapacityForecastProjectWorkload(
                    project: $0.project,
                    dueSeconds: $0.seconds,
                    taskCount: $0.count,
                    unknownDurationCount: $0.unknowns
                )
            }
            .sorted {
                if $0.dueSeconds != $1.dueSeconds {
                    return $0.dueSeconds > $1.dueSeconds
                }
                return $0.project.displayName.localizedCaseInsensitiveCompare($1.project.displayName) == .orderedAscending
            }
    }

    private func makeCohortAccumulators(
        from tasks: [ResolvedForecastTask],
        inputs: [DayCapacityForecastDayInput]
    ) -> [CohortAccumulator] {
        var grouped: [String: CohortAccumulator] = [:]

        for task in tasks {
            let deadlineDate: Date
            deadlineDate = effectiveForecastDeadline(for: task, inputs: inputs)
            let key = "\(task.task.project.id?.uuidString ?? "name:\(task.task.project.displayName)")|\(deadlineDate.timeIntervalSinceReferenceDate)"
            var accumulator = grouped[key] ?? CohortAccumulator(
                project: task.task.project,
                dayIndex: task.dayIndex,
                deadlineDate: deadlineDate,
                workloadSeconds: 0,
                unknownDurationCount: 0
            )
            accumulator.workloadSeconds += task.duration
            if task.isUnknown {
                accumulator.unknownDurationCount += 1
            }
            grouped[key] = accumulator
        }

        return grouped.values.sorted {
            if $0.dayIndex != $1.dayIndex {
                return $0.dayIndex < $1.dayIndex
            }
            if $0.deadlineDate != $1.deadlineDate {
                return $0.deadlineDate < $1.deadlineDate
            }
            return $0.project.displayName.localizedCaseInsensitiveCompare($1.project.displayName) == .orderedAscending
        }
    }

    private func effectiveForecastDeadline(
        for task: ResolvedForecastTask,
        inputs: [DayCapacityForecastDayInput]
    ) -> Date {
        if task.isOverdue || !hasSpecificTime(task.task.dueDate) {
            return inputs[task.dayIndex].window.end
        }
        return min(task.task.dueDate, inputs[task.dayIndex].window.end)
    }

    private func beginByDate(
        workloadSeconds: TimeInterval,
        dayIndex: Int,
        deadline: Date,
        inputs: [DayCapacityForecastDayInput],
        availableByDay: [TimeInterval],
        now: Date
    ) -> BeginByResult {
        guard workloadSeconds > 0 else {
            return BeginByResult(latestSafeStartDate: nil, isInsufficientCapacity: false)
        }

        var remaining = workloadSeconds
        var latestSafeStartDate: Date?
        let effectiveDeadline = hasSpecificTime(deadline) ? deadline : inputs[dayIndex].window.end

        for index in stride(from: dayIndex, through: 0, by: -1) {
            let capacity = index == dayIndex
                ? availableSeconds(
                    for: inputs[index],
                    start: index == 0 ? max(inputs[index].window.start, now) : inputs[index].window.start,
                    end: effectiveDeadline >= inputs[index].window.end ? inputs[index].window.end : effectiveDeadline
                )
                : availableByDay[index]

            guard capacity > 0 else { continue }
            latestSafeStartDate = inputs[index].window.labelDate
            remaining -= capacity
            if remaining <= 0 {
                return BeginByResult(
                    latestSafeStartDate: latestSafeStartDate,
                    isInsufficientCapacity: false
                )
            }
        }

        return BeginByResult(
            latestSafeStartDate: nil,
            isInsufficientCapacity: true
        )
    }

    private func pressureRatio(dueSeconds: TimeInterval, capacitySeconds: TimeInterval) -> Double {
        guard capacitySeconds > 0 else {
            return dueSeconds > 0 ? .infinity : 0
        }
        return dueSeconds / capacitySeconds
    }

    private func pressureStatus(for ratio: Double) -> DayCapacityForecastDay.PressureStatus {
        if ratio > 1.0 {
            return .overloaded
        }
        if ratio >= 0.85 {
            return .tight
        }
        return .comfortable
    }

    private func hasSpecificTime(_ date: Date) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 || (components.second ?? 0) != 0
    }
}

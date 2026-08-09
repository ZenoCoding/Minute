import XCTest
@testable import Minute

final class DayCapacityForecastTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var service: DayCapacityService {
        DayCapacityService(calendar: calendar)
    }

    func testCumulativeWorkOverloadsBySecondDay() {
        let inputs = makeInputs(hoursPerDay: 2)
        let project = DayCapacityForecastProject(name: "School")
        let tasks = [
            task(dayOffset: 0, duration: 2 * 60 * 60, project: project),
            task(dayOffset: 1, duration: 3 * 60 * 60, project: project)
        ]

        let forecast = calculate(tasks: tasks, inputs: inputs)

        XCTAssertEqual(forecast.days[0].cumulativeDueSeconds, 2 * 60 * 60)
        XCTAssertEqual(forecast.days[1].cumulativeDueSeconds, 5 * 60 * 60)
        XCTAssertEqual(forecast.days[1].cumulativeCapacitySeconds, 4 * 60 * 60)
        XCTAssertEqual(forecast.days[1].status, .overloaded)
    }

    func testEightyFivePercentIsTight() {
        let inputs = makeInputs(hoursPerDay: 100.0 / 60.0)
        let task = task(dayOffset: 0, duration: 85 * 60, project: DayCapacityForecastProject(name: "Essay"))

        let forecast = calculate(tasks: [task], inputs: inputs)

        XCTAssertEqual(forecast.days[0].pressureRatio, 0.85, accuracy: 0.0001)
        XCTAssertEqual(forecast.days[0].status, .tight)
    }

    func testOverdueWorkRollsIntoFirstForecastDay() {
        let inputs = makeInputs(hoursPerDay: 2)
        let overdueDate = date(dayOffset: -1, hour: 0)
        let task = DayCapacityForecastTask(
            dueDate: overdueDate,
            estimatedDuration: 45 * 60,
            project: DayCapacityForecastProject(name: "Overdue")
        )

        let forecast = calculate(tasks: [task], inputs: inputs)

        XCTAssertEqual(forecast.days[0].dueOnDaySeconds, 45 * 60)
        XCTAssertEqual(forecast.days.dropFirst().reduce(0) { $0 + $1.dueOnDaySeconds }, 0)
    }

    func testBusyIntervalsReduceCapacityAndMergeOverlap() {
        var inputs = makeInputs(hoursPerDay: 3)
        let dayStart = calendar.startOfDay(for: date(dayOffset: 0, hour: 0))
        let busyStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayStart)!
        let busyEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!
        inputs[0] = DayCapacityForecastDayInput(
            window: inputs[0].window,
            busyIntervals: [
                DateInterval(start: busyStart, end: busyStart.addingTimeInterval(60 * 60)),
                DateInterval(start: busyStart.addingTimeInterval(30 * 60), end: busyEnd)
            ]
        )

        let forecast = calculate(tasks: [], inputs: inputs)

        XCTAssertEqual(forecast.days[0].availableSeconds, 60 * 60, accuracy: 0.001)
    }

    func testUnknownDurationIsCountedAndFallbackIsOptionalEstimate() {
        let inputs = makeInputs(hoursPerDay: 2)
        let task = task(dayOffset: 0, duration: nil, project: DayCapacityForecastProject(name: "Unknown"))

        let withoutFallback = calculate(tasks: [task], inputs: inputs, useFallbackDuration: false)
        XCTAssertEqual(withoutFallback.days[0].unknownDurationCount, 1)
        XCTAssertEqual(withoutFallback.days[0].dueOnDaySeconds, 0)
        XCTAssertTrue(withoutFallback.hasUnknownDurations)

        let withFallback = calculate(tasks: [task], inputs: inputs, useFallbackDuration: true, fallbackDurationMinutes: 30)
        XCTAssertEqual(withFallback.days[0].unknownDurationCount, 1)
        XCTAssertEqual(withFallback.days[0].dueOnDaySeconds, 30 * 60)
        XCTAssertTrue(withFallback.usesFallbackDuration)
    }

    func testBeginByWalksCapacityBackwardByProjectCohort() {
        let inputs = makeInputs(hoursPerDay: 2)
        let project = DayCapacityForecastProject(name: "Research")
        let task = task(dayOffset: 2, duration: 3 * 60 * 60, project: project)

        let forecast = calculate(tasks: [task], inputs: inputs)
        guard let cohort = forecast.cohorts.first else {
            return XCTFail("Expected a project deadline cohort")
        }
        XCTAssertEqual(cohort.project.name, "Research")
        XCTAssertEqual(cohort.latestSafeStartDate, inputs[1].window.labelDate)
        XCTAssertFalse(cohort.isInsufficientCapacity)
    }

    func testTimedDeadlineUsesCapacityBeforeActualTime() {
        let inputs = makeInputs(hoursPerDay: 8)
        let timedTask = task(dayOffset: 0, hour: 10, duration: 2 * 60 * 60, project: DayCapacityForecastProject(name: "Timed"))

        let forecast = calculate(tasks: [timedTask], inputs: inputs)

        XCTAssertEqual(forecast.days[0].availableSecondsForDeadlines, 60 * 60, accuracy: 0.001)
        XCTAssertEqual(forecast.days[0].status, .overloaded)
    }

    func testNoDatedTasksProducesNeutralSevenDayForecast() {
        let forecast = calculate(tasks: [], inputs: makeInputs(hoursPerDay: 2))

        XCTAssertFalse(forecast.hasDatedTasks)
        XCTAssertTrue(forecast.cohorts.isEmpty)
        XCTAssertEqual(forecast.days.count, 7)
        XCTAssertTrue(forecast.days.allSatisfy { $0.status == .comfortable })
    }

    private func calculate(
        tasks: [DayCapacityForecastTask],
        inputs: [DayCapacityForecastDayInput],
        useFallbackDuration: Bool = false,
        fallbackDurationMinutes: Int = 30
    ) -> DayCapacityForecast {
        service.calculate(
            now: date(dayOffset: 0, hour: 9),
            tasks: tasks,
            dayInputs: inputs,
            useFallbackDuration: useFallbackDuration,
            fallbackDurationMinutes: fallbackDurationMinutes
        )
    }

    private func makeInputs(hoursPerDay: Double) -> [DayCapacityForecastDayInput] {
        (0..<7).map { offset in
            let start = date(dayOffset: offset, hour: 9)
            let end = start.addingTimeInterval(hoursPerDay * 60 * 60)
            return DayCapacityForecastDayInput(
                window: PlanningDayWindow(
                    start: start,
                    end: end,
                    labelDate: calendar.startOfDay(for: start),
                    isOffHours: false
                )
            )
        }
    }

    private func task(
        dayOffset: Int,
        hour: Int = 0,
        duration: TimeInterval?,
        project: DayCapacityForecastProject
    ) -> DayCapacityForecastTask {
        DayCapacityForecastTask(
            dueDate: date(dayOffset: dayOffset, hour: hour),
            estimatedDuration: duration,
            project: project
        )
    }

    private func date(dayOffset: Int, hour: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        return calendar.date(byAdding: .day, value: dayOffset, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!)!
    }
}

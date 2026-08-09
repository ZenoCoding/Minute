import XCTest
@testable import Minute

final class ComposerDateScrollInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 9,
            hour: 14
        ).date!
    }

    func testForwardScrollMovesFromNoDateThroughTodayAndTomorrow() {
        let today = ComposerDraftDateStepper.date(
            afterApplying: 1,
            to: nil,
            now: now,
            calendar: calendar
        )
        let tomorrow = ComposerDraftDateStepper.date(
            afterApplying: 1,
            to: today,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(today, calendar.startOfDay(for: now))
        XCTAssertEqual(
            tomorrow,
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        )
    }

    func testBackwardScrollReturnsTodayToNoDateAndDoesNotEnterThePast() {
        let today = calendar.startOfDay(for: now)
        XCTAssertNil(
            ComposerDraftDateStepper.date(
                afterApplying: -1,
                to: today,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertNil(
            ComposerDraftDateStepper.date(
                afterApplying: -4,
                to: nil,
                now: now,
                calendar: calendar
            )
        )
    }

    func testMultiStepScrollCrossesSeveralCalendarDays() {
        let result = ComposerDraftDateStepper.date(
            afterApplying: 4,
            to: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(
            result,
            calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))
        )
    }

    func testPreciseScrollingRequiresThresholdAndRetainsRemainder() {
        var accumulator = ComposerDateScrollAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 10, isPrecise: true), 0)
        XCTAssertEqual(accumulator.consume(delta: 20, isPrecise: true), 1)
        XCTAssertEqual(accumulator.consume(delta: 26, isPrecise: true), 1)
        XCTAssertEqual(accumulator.accumulatedDelta, 0, accuracy: 0.001)
    }

    func testMouseWheelNotchAlwaysProducesOneStep() {
        var accumulator = ComposerDateScrollAccumulator()
        XCTAssertEqual(accumulator.consume(delta: 0.1, isPrecise: false), 1)
        XCTAssertEqual(accumulator.consume(delta: -3, isPrecise: false), -1)
    }
}

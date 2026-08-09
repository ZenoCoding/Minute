import XCTest
@testable import Minute

final class TaskActionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testReschedulingDayOnlyDeadlineStaysDayOnly() {
        let source = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 18))!

        let result = DueDateSupport.rescheduledDate(
            from: source,
            to: target,
            calendar: calendar
        )

        XCTAssertEqual(result, calendar.startOfDay(for: target))
        XCTAssertTrue(DueDateSupport.isDayOnly(result, calendar: calendar))
    }

    func testReschedulingTimedDeadlinePreservesWallClockTime() {
        let source = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 9, hour: 14, minute: 35, second: 12)
        )!
        let target = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!

        let result = DueDateSupport.rescheduledDate(
            from: source,
            to: target,
            calendar: calendar
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 35)
        XCTAssertEqual(components.second, 12)
        XCTAssertFalse(DueDateSupport.isDayOnly(result, calendar: calendar))
    }

    func testReschedulingAcrossDaylightSavingPreservesWallClockTime() {
        var daylightSavingCalendar = Calendar(identifier: .gregorian)
        daylightSavingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let source = daylightSavingCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 7, hour: 14, minute: 35)
        )!
        let target = daylightSavingCalendar.date(
            from: DateComponents(year: 2026, month: 3, day: 9)
        )!

        let result = DueDateSupport.rescheduledDate(
            from: source,
            to: target,
            calendar: daylightSavingCalendar
        )
        let components = daylightSavingCalendar.dateComponents([.hour, .minute], from: result)

        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 35)
    }

    func testNextSaturdayAlwaysMeansAnUpcomingSaturday() {
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 10))!
        let result = DueDateSupport.presetNextSaturday(now: saturday, calendar: calendar)

        XCTAssertEqual(calendar.component(.weekday, from: result), 7)
        XCTAssertEqual(calendar.dateComponents([.day], from: result).day, 15)
        XCTAssertTrue(DueDateSupport.isDayOnly(result, calendar: calendar))
    }
}

import XCTest
@testable import Heartbeat

final class ActiveHoursTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func test_contains_returnsTrue_withinRange() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertTrue(hours.contains(date(hour: 12, minute: 30), calendar: calendar))
    }

    func test_contains_returnsFalse_beforeStart() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertFalse(hours.contains(date(hour: 7, minute: 59), calendar: calendar))
    }

    func test_contains_returnsFalse_atOrAfterEnd() {
        let hours = ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        XCTAssertFalse(hours.contains(date(hour: 17, minute: 0), calendar: calendar))
    }

    func test_currentIntervalSeconds_usesNormalInterval_inNormalMode() {
        let settings = SchedulerSettings(
            mode: .normal,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0),
            weekdaysOnly: false
        )
        XCTAssertEqual(settings.currentIntervalSeconds, 30 * 60)
    }

    func test_currentIntervalSeconds_usesUrgentInterval_inUrgentMode() {
        let settings = SchedulerSettings(
            mode: .urgent,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0),
            weekdaysOnly: false
        )
        XCTAssertEqual(settings.currentIntervalSeconds, 10 * 60)
    }
}

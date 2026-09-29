import XCTest
@testable import Heartbeat

private final class FakeClock: Clock {
    var fixedDate: Date
    init(_ date: Date) { fixedDate = date }
    func now() -> Date { fixedDate }
}

final class ReminderSchedulerTests: XCTestCase {
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

    private func makeSettings(mode: ReminderMode) -> SchedulerSettings {
        SchedulerSettings(
            mode: mode,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0)
        )
    }

    func test_currentState_isPaused_outsideActiveHours() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .paused)
    }

    func test_currentState_isActiveNormal_insideActiveHoursNormalMode() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
    }

    func test_currentState_isActiveUrgent_insideActiveHoursUrgentMode() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeUrgent)
    }

    func test_tick_firesOnFire_insideActiveHours() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var fired = false
        scheduler.onFire = { fired = true }
        scheduler.tick()
        XCTAssertTrue(fired)
    }

    func test_tick_doesNotFire_outsideActiveHours() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var fired = false
        scheduler.onFire = { fired = true }
        scheduler.tick()
        XCTAssertFalse(fired)
    }

    func test_tick_reportsStateChange() {
        let clock = FakeClock(date(hour: 20, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        var reportedState: ReminderScheduler.SchedulerState?
        scheduler.onStateChange = { reportedState = $0 }
        scheduler.tick()
        XCTAssertEqual(reportedState, .paused)
    }

    func test_reconfigure_changesCurrentState() {
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
        scheduler.reconfigure(makeSettings(mode: .urgent))
        XCTAssertEqual(scheduler.currentState(), .activeUrgent)
    }

    // MARK: - Grid-aligned first fire

    func test_nextAlignedFireDate_skipsBoundaryLessThanOneFullIntervalAway() {
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: FakeClock(date(hour: 12, minute: 0)))
        // Start at 10:55, 10-min interval: 11:00 is only 5 min away (< 1 interval), so it's skipped.
        let fireDate = scheduler.nextAlignedFireDate(intervalSeconds: 10 * 60, after: date(hour: 10, minute: 55))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: fireDate), DateComponents(hour: 11, minute: 10))
    }

    func test_nextAlignedFireDate_hitsExactBoundary_whenExactlyOneIntervalAway() {
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: FakeClock(date(hour: 12, minute: 0)))
        // Start at 10:50, 10-min interval: 11:00 is exactly one interval away, so it's used as-is.
        let fireDate = scheduler.nextAlignedFireDate(intervalSeconds: 10 * 60, after: date(hour: 10, minute: 50))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: fireDate), DateComponents(hour: 11, minute: 0))
    }

    func test_nextAlignedFireDate_alignsToIntervalGrid_forLongerInterval() {
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: FakeClock(date(hour: 12, minute: 0)))
        // Start at 10:35, 30-min interval: grid is :00/:30, earliest is 11:05, next grid point is 11:30.
        let fireDate = scheduler.nextAlignedFireDate(intervalSeconds: 30 * 60, after: date(hour: 10, minute: 35))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: fireDate), DateComponents(hour: 11, minute: 30))
    }
}

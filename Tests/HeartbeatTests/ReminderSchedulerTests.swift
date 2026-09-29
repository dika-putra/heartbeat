import XCTest
@testable import Heartbeat

private final class FakeClock: Clock {
    var fixedDate: Date
    init(_ date: Date) { fixedDate = date }
    func now() -> Date { fixedDate }
}

final class ReminderSchedulerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    // 2026-09-29 is a Tuesday; 2026-10-03/04 are Saturday/Sunday.
    private func date(year: Int = 2026, month: Int = 9, day: Int = 29, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func makeSettings(mode: ReminderMode, weekdaysOnly: Bool = false) -> SchedulerSettings {
        SchedulerSettings(
            mode: mode,
            normalIntervalMinutes: 30,
            urgentIntervalMinutes: 10,
            activeHours: ActiveHours(startHour: 8, startMinute: 0, endHour: 17, endMinute: 0),
            weekdaysOnly: weekdaysOnly
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

    // MARK: - nextFireDate() for menu display

    func test_nextFireDate_isNil_beforeStart() {
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: FakeClock(date(hour: 12, minute: 0)))
        XCTAssertNil(scheduler.nextFireDate())
    }

    func test_nextFireDate_matchesFirstAlignedFireDate_rightAfterStart() {
        let clock = FakeClock(date(hour: 10, minute: 55))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: clock)
        scheduler.start()
        defer { scheduler.stop() }

        // 10-min interval starting at 10:55 aligns to 11:10 (see grid-aligned tests above).
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: scheduler.nextFireDate()!), DateComponents(hour: 11, minute: 10))
    }

    func test_nextFireDate_advancesToNextGridBoundary_asTimePasses() {
        let clock = FakeClock(date(hour: 10, minute: 55))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .urgent), clock: clock)
        scheduler.start()
        defer { scheduler.stop() }

        // First boundary (11:10) has passed; steady-state fires are every 10 min after that.
        clock.fixedDate = date(hour: 11, minute: 15)
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: scheduler.nextFireDate()!), DateComponents(hour: 11, minute: 20))
    }

    // MARK: - Weekdays-only

    func test_currentState_isActive_onWeekend_whenWeekdaysOnlyIsOff() {
        // 2026-10-03 is a Saturday.
        let clock = FakeClock(date(month: 10, day: 3, hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal, weekdaysOnly: false), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
    }

    func test_currentState_isPaused_onSaturday_whenWeekdaysOnlyIsOn() {
        let clock = FakeClock(date(month: 10, day: 3, hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal, weekdaysOnly: true), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .paused)
    }

    func test_currentState_isPaused_onSunday_whenWeekdaysOnlyIsOn() {
        // 2026-10-04 is a Sunday.
        let clock = FakeClock(date(month: 10, day: 4, hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal, weekdaysOnly: true), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .paused)
    }

    func test_currentState_isActive_onWeekday_whenWeekdaysOnlyIsOn() {
        // 2026-09-29 is a Tuesday.
        let clock = FakeClock(date(hour: 12, minute: 0))
        let scheduler = ReminderScheduler(settings: makeSettings(mode: .normal, weekdaysOnly: true), clock: clock)
        XCTAssertEqual(scheduler.currentState(), .activeNormal)
    }

    func test_pauseReason_distinguishesWeekendFromOutsideActiveHours() {
        let weekendClock = FakeClock(date(month: 10, day: 3, hour: 12, minute: 0))
        let weekendScheduler = ReminderScheduler(settings: makeSettings(mode: .normal, weekdaysOnly: true), clock: weekendClock)
        XCTAssertEqual(weekendScheduler.pauseReason(), .weekend)

        let nightClock = FakeClock(date(hour: 20, minute: 0))
        let nightScheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: nightClock)
        XCTAssertEqual(nightScheduler.pauseReason(), .outsideActiveHours)

        let activeClock = FakeClock(date(hour: 12, minute: 0))
        let activeScheduler = ReminderScheduler(settings: makeSettings(mode: .normal), clock: activeClock)
        XCTAssertNil(activeScheduler.pauseReason())
    }
}

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
}

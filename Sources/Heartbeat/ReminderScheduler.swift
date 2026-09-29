import Foundation

protocol Clock {
    func now() -> Date
}

struct SystemClock: Clock {
    func now() -> Date { Date() }
}

final class ReminderScheduler {
    enum SchedulerState {
        case activeNormal
        case activeUrgent
        case paused
    }

    var onFire: (() -> Void)?
    var onStateChange: ((SchedulerState) -> Void)?

    private let clock: Clock
    private var settings: SchedulerSettings
    private var timer: DispatchSourceTimer?

    init(settings: SchedulerSettings, clock: Clock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    func currentState() -> SchedulerState {
        guard settings.activeHours.contains(clock.now()) else { return .paused }
        return settings.mode == .normal ? .activeNormal : .activeUrgent
    }

    func reconfigure(_ newSettings: SchedulerSettings) {
        settings = newSettings
        if timer != nil {
            stop()
            start()
        }
    }

    func tick() {
        let state = currentState()
        onStateChange?(state)
        guard state != .paused else { return }
        onFire?()
    }

    /// Smallest multiple of `intervalSeconds` since local midnight that is at
    /// least one full interval after `referenceDate` — e.g. starting at 10:55
    /// with a 10-minute interval fires first at 11:10, not 11:00 (only 5 min
    /// away) or 11:05 (unaligned to the grid).
    func nextAlignedFireDate(intervalSeconds: TimeInterval, after referenceDate: Date, calendar: Calendar = .current) -> Date {
        let earliestFireDate = referenceDate.addingTimeInterval(intervalSeconds)
        let startOfDay = calendar.startOfDay(for: earliestFireDate)
        let secondsSinceStartOfDay = earliestFireDate.timeIntervalSince(startOfDay)
        let intervalsElapsed = (secondsSinceStartOfDay / intervalSeconds).rounded(.up)
        return startOfDay.addingTimeInterval(intervalsElapsed * intervalSeconds)
    }

    private var firstFireDate: Date?

    func start() {
        let intervalSeconds = settings.currentIntervalSeconds
        let fireDate = nextAlignedFireDate(intervalSeconds: intervalSeconds, after: clock.now())
        firstFireDate = fireDate
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + fireDate.timeIntervalSince(clock.now()), repeating: intervalSeconds)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// The next time a reminder is scheduled to fire, for display purposes
    /// (e.g. "Next reminder: 11:20" in the menu). `nil` before `start()` is
    /// called. Computed from the first aligned fire date rather than tracked
    /// per-tick, so it stays correct no matter when it's queried.
    func nextFireDate() -> Date? {
        guard let firstFireDate else { return nil }
        let intervalSeconds = settings.currentIntervalSeconds
        let elapsed = clock.now().timeIntervalSince(firstFireDate)
        guard elapsed >= 0 else { return firstFireDate }
        let intervalsPassed = (elapsed / intervalSeconds).rounded(.down) + 1
        return firstFireDate.addingTimeInterval(intervalsPassed * intervalSeconds)
    }
}

extension ReminderScheduler.SchedulerState: Equatable {}

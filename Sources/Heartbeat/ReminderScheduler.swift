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

    func start() {
        let intervalSeconds = settings.currentIntervalSeconds
        let fireDate = nextAlignedFireDate(intervalSeconds: intervalSeconds, after: clock.now())
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
}

extension ReminderScheduler.SchedulerState: Equatable {}

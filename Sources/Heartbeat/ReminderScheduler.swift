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

    func start() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + settings.currentIntervalSeconds, repeating: settings.currentIntervalSeconds)
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

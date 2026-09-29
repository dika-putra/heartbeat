import Foundation

enum ReminderMode: String, Codable {
    case normal
    case urgent
}

enum NotificationActionType: String, Codable {
    case none
    case openURL
    case openApp
}

struct SchedulerSettings {
    var mode: ReminderMode
    var normalIntervalMinutes: Int
    var urgentIntervalMinutes: Int
    var activeHours: ActiveHours

    var currentIntervalSeconds: TimeInterval {
        let minutes = mode == .normal ? normalIntervalMinutes : urgentIntervalMinutes
        return TimeInterval(minutes * 60)
    }
}

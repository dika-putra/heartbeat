import Foundation

struct HeartbeatSettings: Codable, Equatable {
    var mode: ReminderMode
    var normalIntervalMinutes: Int
    var urgentIntervalMinutes: Int
    var activeHoursStartHour: Int
    var activeHoursStartMinute: Int
    var activeHoursEndHour: Int
    var activeHoursEndMinute: Int
    var message: String
    var soundName: String
    var launchAtLogin: Bool

    static let `default` = HeartbeatSettings(
        mode: .normal,
        normalIntervalMinutes: 30,
        urgentIntervalMinutes: 10,
        activeHoursStartHour: 8,
        activeHoursStartMinute: 0,
        activeHoursEndHour: 17,
        activeHoursEndMinute: 0,
        message: "Waktunya cek kerjaanmu!",
        soundName: "Glass",
        launchAtLogin: true
    )

    var activeHours: ActiveHours {
        ActiveHours(
            startHour: activeHoursStartHour,
            startMinute: activeHoursStartMinute,
            endHour: activeHoursEndHour,
            endMinute: activeHoursEndMinute
        )
    }

    var schedulerSettings: SchedulerSettings {
        SchedulerSettings(
            mode: mode,
            normalIntervalMinutes: normalIntervalMinutes,
            urgentIntervalMinutes: urgentIntervalMinutes,
            activeHours: activeHours
        )
    }
}

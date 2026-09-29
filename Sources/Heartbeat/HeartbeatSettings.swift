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
    var actionType: NotificationActionType
    var actionValue: String

    init(
        mode: ReminderMode,
        normalIntervalMinutes: Int,
        urgentIntervalMinutes: Int,
        activeHoursStartHour: Int,
        activeHoursStartMinute: Int,
        activeHoursEndHour: Int,
        activeHoursEndMinute: Int,
        message: String,
        soundName: String,
        launchAtLogin: Bool,
        actionType: NotificationActionType = .none,
        actionValue: String = ""
    ) {
        self.mode = mode
        self.normalIntervalMinutes = normalIntervalMinutes
        self.urgentIntervalMinutes = urgentIntervalMinutes
        self.activeHoursStartHour = activeHoursStartHour
        self.activeHoursStartMinute = activeHoursStartMinute
        self.activeHoursEndHour = activeHoursEndHour
        self.activeHoursEndMinute = activeHoursEndMinute
        self.message = message
        self.soundName = soundName
        self.launchAtLogin = launchAtLogin
        self.actionType = actionType
        self.actionValue = actionValue
    }

    // Custom decoding so settings saved before `actionType`/`actionValue`
    // existed still load instead of silently falling back to `.default`
    // and wiping the user's saved preferences.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ReminderMode.self, forKey: .mode)
        normalIntervalMinutes = try container.decode(Int.self, forKey: .normalIntervalMinutes)
        urgentIntervalMinutes = try container.decode(Int.self, forKey: .urgentIntervalMinutes)
        activeHoursStartHour = try container.decode(Int.self, forKey: .activeHoursStartHour)
        activeHoursStartMinute = try container.decode(Int.self, forKey: .activeHoursStartMinute)
        activeHoursEndHour = try container.decode(Int.self, forKey: .activeHoursEndHour)
        activeHoursEndMinute = try container.decode(Int.self, forKey: .activeHoursEndMinute)
        message = try container.decode(String.self, forKey: .message)
        soundName = try container.decode(String.self, forKey: .soundName)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        actionType = try container.decodeIfPresent(NotificationActionType.self, forKey: .actionType) ?? .none
        actionValue = try container.decodeIfPresent(String.self, forKey: .actionValue) ?? ""
    }

    static let `default` = HeartbeatSettings(
        mode: .normal,
        normalIntervalMinutes: 30,
        urgentIntervalMinutes: 10,
        activeHoursStartHour: 8,
        activeHoursStartMinute: 0,
        activeHoursEndHour: 17,
        activeHoursEndMinute: 0,
        message: "Waktunya cek kerjaanmu! [HH:mm]",
        soundName: "Glass",
        launchAtLogin: true,
        actionType: .none,
        actionValue: ""
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

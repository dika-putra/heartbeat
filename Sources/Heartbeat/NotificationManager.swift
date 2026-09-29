import UserNotifications

final class NotificationManager {
    static let reminderIdentifier = "heartbeat-reminder"

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func makeRequest(message: String, soundName: String?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Heartbeat"
        content.body = message
        if let soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }
        return UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: nil)
    }

    func fire(message: String, soundName: String?) {
        let expandedMessage = Self.expandTimestampTokens(in: message, now: Date())
        let request = makeRequest(message: expandedMessage, soundName: soundName)
        UNUserNotificationCenter.current().add(request)
    }

    /// Replaces bracketed date-format tokens like `[HH:mm]` or `[HH:mm:ss]`
    /// with the current time, so users can embed a timestamp in their
    /// reminder message. Any valid `DateFormatter` pattern works.
    static func expandTimestampTokens(in message: String, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var result = ""
        var remainder = Substring(message)
        while let openBracket = remainder.firstIndex(of: "["),
              let closeBracket = remainder[remainder.index(after: openBracket)...].firstIndex(of: "]") {
            result += remainder[remainder.startIndex..<openBracket]
            let token = String(remainder[remainder.index(after: openBracket)..<closeBracket])
            formatter.dateFormat = token
            result += formatter.string(from: now)
            remainder = remainder[remainder.index(after: closeBracket)...]
        }
        result += remainder
        return result
    }
}

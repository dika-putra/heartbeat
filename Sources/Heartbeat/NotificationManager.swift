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
        let request = makeRequest(message: message, soundName: soundName)
        UNUserNotificationCenter.current().add(request)
    }
}

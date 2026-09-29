import Foundation

final class SettingsStore {
    private static let key = "com.heartbeat.settings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HeartbeatSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(HeartbeatSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: HeartbeatSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

import XCTest
@testable import Heartbeat

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.heartbeat.tests.settingsstore"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_load_returnsDefault_whenNothingSaved() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), HeartbeatSettings.default)
    }

    func test_save_thenLoad_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        var settings = HeartbeatSettings.default
        settings.mode = .urgent
        settings.message = "Custom message"
        settings.urgentIntervalMinutes = 5

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func test_save_thenLoad_roundTripsNotificationAction() {
        let store = SettingsStore(defaults: defaults)
        var settings = HeartbeatSettings.default
        settings.actionType = .openURL
        settings.actionValue = "https://example.com"

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func test_load_migratesSettingsSavedBeforeActionFieldsExisted() {
        let oldSchemaJSON = """
        {"mode":"normal","normalIntervalMinutes":30,"urgentIntervalMinutes":10,\
        "activeHoursStartHour":8,"activeHoursStartMinute":0,"activeHoursEndHour":17,\
        "activeHoursEndMinute":0,"message":"Old message","soundName":"Pop","launchAtLogin":true}
        """
        defaults.set(Data(oldSchemaJSON.utf8), forKey: "com.heartbeat.settings")

        let store = SettingsStore(defaults: defaults)
        let loaded = store.load()

        XCTAssertEqual(loaded.soundName, "Pop")
        XCTAssertEqual(loaded.message, "Old message")
        XCTAssertEqual(loaded.actionType, .none)
        XCTAssertEqual(loaded.actionValue, "")
    }
}

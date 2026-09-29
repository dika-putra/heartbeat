import XCTest
import UserNotifications
@testable import Heartbeat

final class NotificationManagerTests: XCTestCase {
    func test_makeRequest_usesFixedIdentifier() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.identifier, NotificationManager.reminderIdentifier)
    }

    func test_makeRequest_setsBodyToMessage() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.content.body, "Cek kerjaan")
    }

    func test_makeRequest_usesDefaultSound_whenSoundNameIsNil() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertEqual(request.content.sound, .default)
    }

    func test_makeRequest_usesNamedSound_whenSoundNameProvided() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: "Glass")
        XCTAssertEqual(request.content.sound, UNNotificationSound(named: UNNotificationSoundName("Glass")))
    }

    func test_makeRequest_hasNilTrigger_forImmediateDelivery() {
        let manager = NotificationManager()
        let request = manager.makeRequest(message: "Cek kerjaan", soundName: nil)
        XCTAssertNil(request.trigger)
    }
}

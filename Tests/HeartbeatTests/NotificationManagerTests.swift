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

    // MARK: - Timestamp token expansion

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = 11
        components.minute = 5
        components.second = 9
        return components.date!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func test_expandTimestampTokens_replacesHHmm() {
        let result = NotificationManager.expandTimestampTokens(in: "Cek kerjaan [HH:mm]", now: fixedDate(), calendar: utcCalendar())
        XCTAssertEqual(result, "Cek kerjaan 11:05")
    }

    func test_expandTimestampTokens_replacesHHmmss() {
        let result = NotificationManager.expandTimestampTokens(in: "Cek kerjaan [HH:mm:ss]", now: fixedDate(), calendar: utcCalendar())
        XCTAssertEqual(result, "Cek kerjaan 11:05:09")
    }

    func test_expandTimestampTokens_leavesPlainMessageUnchanged() {
        let result = NotificationManager.expandTimestampTokens(in: "Cek kerjaan", now: fixedDate(), calendar: utcCalendar())
        XCTAssertEqual(result, "Cek kerjaan")
    }

    func test_expandTimestampTokens_replacesMultipleTokens() {
        let result = NotificationManager.expandTimestampTokens(in: "[HH:mm] cek kerjaan, sekarang [HH:mm:ss]", now: fixedDate(), calendar: utcCalendar())
        XCTAssertEqual(result, "11:05 cek kerjaan, sekarang 11:05:09")
    }

    func test_fire_expandsTokensInMessage_beforeBuildingRequest() {
        let manager = NotificationManager()
        let request = manager.makeRequest(
            message: NotificationManager.expandTimestampTokens(in: "Cek kerjaan [HH:mm]", now: fixedDate(), calendar: utcCalendar()),
            soundName: nil
        )
        XCTAssertEqual(request.content.body, "Cek kerjaan 11:05")
    }
}

import XCTest
@testable import Heartbeat

final class ScaffoldTests: XCTestCase {
    func test_appDelegate_canBeInstantiated() {
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate)
    }
}

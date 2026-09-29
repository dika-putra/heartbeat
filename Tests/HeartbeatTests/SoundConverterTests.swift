import XCTest
@testable import Heartbeat

final class SoundConverterTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func test_convertToCaf_throwsTooLong_whenDurationExceeds30Seconds() {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 45.0 }
        converter.processRunner = { _, _ in 0 }

        XCTAssertThrowsError(
            try converter.convertToCaf(sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"), destinationDirectory: tempDirectory)
        ) { error in
            XCTAssertEqual(error as? SoundConverterError, .tooLong)
        }
    }

    func test_convertToCaf_throwsConversionFailed_whenProcessExitsNonZero() {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 1 }

        XCTAssertThrowsError(
            try converter.convertToCaf(sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"), destinationDirectory: tempDirectory)
        ) { error in
            XCTAssertEqual(error as? SoundConverterError, .conversionFailed)
        }
    }

    func test_convertToCaf_returnsCafDestinationURL_onSuccess() throws {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 0 }

        let result = try converter.convertToCaf(
            sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"),
            destinationDirectory: tempDirectory
        )

        XCTAssertEqual(result, tempDirectory.appendingPathComponent("sound.caf"))
    }

    func test_convertToCaf_createsDestinationDirectory_ifMissing() throws {
        var converter = SoundConverter()
        converter.durationProvider = { _ in 10.0 }
        converter.processRunner = { _, _ in 0 }

        _ = try converter.convertToCaf(
            sourceURL: URL(fileURLWithPath: "/tmp/sound.mp3"),
            destinationDirectory: tempDirectory
        )

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && isDirectory.boolValue)
    }
}

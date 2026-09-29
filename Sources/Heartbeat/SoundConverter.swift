import AVFoundation
import Foundation

enum SoundConverterError: Error, Equatable {
    case tooLong
    case conversionFailed
}

struct SoundConverter {
    static let maxDurationSeconds: Double = 30

    var durationProvider: (URL) -> Double = { url in
        let seconds = AVURLAsset(url: url).duration.seconds
        return seconds.isFinite ? seconds : .infinity
    }

    var processRunner: (URL, [String]) throws -> Int32 = { executable, arguments in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func convertToCaf(sourceURL: URL, destinationDirectory: URL) throws -> URL {
        let duration = durationProvider(sourceURL)
        guard duration.isFinite, duration <= Self.maxDurationSeconds else {
            throw SoundConverterError.tooLong
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("caf")

        let status = try processRunner(
            URL(fileURLWithPath: "/usr/bin/afconvert"),
            ["-f", "caff", "-d", "LEI16", sourceURL.path, destinationURL.path]
        )
        guard status == 0 else { throw SoundConverterError.conversionFailed }

        return destinationURL
    }
}

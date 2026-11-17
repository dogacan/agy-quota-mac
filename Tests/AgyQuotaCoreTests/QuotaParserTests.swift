import Foundation
import XCTest
@testable import AgyQuotaCore

final class QuotaParserTests: XCTestCase {
    func testParsesRealWorldAgyQuotaOutput() throws {
        let sample = """
        Quota:
        Gemini Models          Weekly Limit Remaining     97%   2026-11-21 13:05 PST
        Gemini Models          Five Hour Limit Remaining  87%   2026-11-14 18:05 PST
        Claude and GPT models  Weekly Limit Remaining     100%  2026-11-21 15:16 PST
        Claude and GPT models  Five Hour Limit Remaining  100%  2026-11-14 20:16 PST
        """

        let snapshot = try QuotaParser.parse(sample)

        let gemini = try XCTUnwrap(snapshot.gemini)
        XCTAssertEqual(gemini.title, "Gemini Models")
        XCTAssertEqual(gemini.fiveHour?.roundedPercent, 87)
        XCTAssertEqual(gemini.weekly?.roundedPercent, 97)
        XCTAssertEqual(gemini.percent(for: .lowest), 87)
        XCTAssertEqual(gemini.percent(for: .fiveHour), 87)
        XCTAssertEqual(gemini.percent(for: .weekly), 97)
        XCTAssertEqual(gemini.windows.map(\.kind), [.fiveHour, .weekly])

        let thirdParty = try XCTUnwrap(snapshot.thirdParty)
        XCTAssertEqual(thirdParty.title, "Claude and GPT models")
        XCTAssertEqual(thirdParty.fiveHour?.roundedPercent, 100)
        XCTAssertEqual(thirdParty.weekly?.roundedPercent, 100)
        XCTAssertEqual(thirdParty.percent(for: .lowest), 100)

        let fiveHourResetDate = try XCTUnwrap(gemini.fiveHour?.resetDate)
        let referenceNow = try XCTUnwrap(QuotaParser.parseResetDate("2026-11-14 15:17 PST"))
        let fiveHourSummary = try XCTUnwrap(gemini.fiveHour?.formattedResetSummary(relativeTo: referenceNow))
        XCTAssertTrue(fiveHourSummary.contains("2h 48m"), "Expected '2h 48m' in '\(fiveHourSummary)'")
        XCTAssertTrue(fiveHourSummary.contains("18:05 PST"), "Expected '18:05 PST' in '\(fiveHourSummary)'")

        let weeklySummary = try XCTUnwrap(gemini.weekly?.formattedResetSummary(relativeTo: referenceNow))
        XCTAssertTrue(weeklySummary.contains("6d 21h"), "Expected '6d 21h' in '\(weeklySummary)'")

        let expiredSummary = gemini.fiveHour?.formattedResetSummary(relativeTo: fiveHourResetDate.addingTimeInterval(60))
        XCTAssertEqual(expiredSummary, "Resetting soon")
    }

    func testStripsANSIEscapeSequences() throws {
        let ansiSample = "\u{001B}[1mQuota:\u{001B}[0m\r\n" +
            "\u{001B}[36mGemini Models\u{001B}[0m          Weekly Limit Remaining     \u{001B}[32m97%\u{001B}[0m   2026-11-21 13:05 PST\r\n" +
            "\u{001B}[36mGemini Models\u{001B}[0m          Five Hour Limit Remaining  \u{001B}[33m42%\u{001B}[0m   2026-11-14 18:05 PST\r\n" +
            "\u{001B}[35mClaude and GPT models\u{001B}[0m  Five Hour Limit Remaining  \u{001B}[31m15%\u{001B}[0m   2026-11-14 20:16 PST\r\n"

        let snapshot = try QuotaParser.parse(ansiSample)

        XCTAssertEqual(snapshot.gemini?.weekly?.roundedPercent, 97)
        XCTAssertEqual(snapshot.gemini?.fiveHour?.roundedPercent, 42)
        XCTAssertEqual(snapshot.gemini?.percent(for: .lowest), 42)
        XCTAssertEqual(snapshot.thirdParty?.fiveHour?.roundedPercent, 15)
    }

    func testParsesRowsWithoutResetTimestamps() throws {
        let sample = """
        Quota:
        Gemini Models          Five Hour Limit Remaining  100%
        Claude and GPT models  Weekly Limit Remaining     64%
        """

        let snapshot = try QuotaParser.parse(sample)

        let geminiFiveHour = try XCTUnwrap(snapshot.gemini?.fiveHour)
        XCTAssertEqual(geminiFiveHour.roundedPercent, 100)
        XCTAssertNil(geminiFiveHour.rawResetText)
        XCTAssertNil(geminiFiveHour.resetDate)
        XCTAssertNil(geminiFiveHour.formattedResetSummary())

        let thirdPartyWeekly = try XCTUnwrap(snapshot.thirdParty?.weekly)
        XCTAssertEqual(thirdPartyWeekly.roundedPercent, 64)
        XCTAssertNil(thirdPartyWeekly.resetDate)
    }

    func testThrowsOnEmptyOrUnrecognizedOutput() {
        XCTAssertThrowsError(try QuotaParser.parse("")) { error in
            XCTAssertEqual(error as? QuotaParserError, .emptyOutput)
        }

        XCTAssertThrowsError(try QuotaParser.parse("   \n\t\n ")) { error in
            XCTAssertEqual(error as? QuotaParserError, .emptyOutput)
        }

        XCTAssertThrowsError(try QuotaParser.parse("Error: not authenticated")) { error in
            guard case .noQuotaEntriesFound = error as? QuotaParserError else {
                return XCTFail("Expected noQuotaEntriesFound, got \(error)")
            }
        }
    }

    func testCustomBinaryPathTakesPriority() {
        let paths = AgyRunner.candidateBinaryPaths(
            customBinaryPath: "~/custom/bin/agy",
            homeDirectory: "/Users/testuser",
            processEnvironment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(paths.first, ("~/custom/bin/agy" as NSString).expandingTildeInPath)
        XCTAssertTrue(paths.contains("/Users/testuser/.gemini/antigravity/bin/agy"))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/agy"))
    }

    func testParsesISO8601UTCResetTimestampsInLocalFormatting() throws {
        let sample = """
        Quota:
        Gemini Models          Five Hour Limit Remaining  83%   2026-11-15T04:30:12Z
        Gemini Models          Weekly Limit Remaining     96%   2026-11-21T21:05:07Z
        """

        let snapshot = try QuotaParser.parse(sample)
        let gemini = try XCTUnwrap(snapshot.gemini)
        let fiveHour = try XCTUnwrap(gemini.fiveHour)
        let weekly = try XCTUnwrap(gemini.weekly)

        XCTAssertNotNil(fiveHour.resetDate)
        XCTAssertNotNil(weekly.resetDate)

        let pacific = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let referenceNow = try XCTUnwrap(QuotaParser.parseResetDate("2026-11-14T23:31:00Z"))

        let fiveHourSummary = try XCTUnwrap(fiveHour.formattedResetSummary(relativeTo: referenceNow, timeZone: pacific))
        XCTAssertTrue(fiveHourSummary.contains("4h 59m"), "Expected '4h 59m' in '\(fiveHourSummary)'")
        XCTAssertTrue(fiveHourSummary.contains("8:30 PM"), "Expected '8:30 PM' in '\(fiveHourSummary)'")
        XCTAssertFalse(fiveHourSummary.contains("T04:30:12Z"), "Unexpected raw UTC string in '\(fiveHourSummary)'")

        let weeklySummary = try XCTUnwrap(weekly.formattedResetSummary(relativeTo: referenceNow, timeZone: pacific))
        XCTAssertTrue(weeklySummary.contains("6d 21h"), "Expected '6d 21h' in '\(weeklySummary)'")
        XCTAssertTrue(weeklySummary.contains("Nov 21, 1:05 PM"), "Expected 'Nov 21, 1:05 PM' in '\(weeklySummary)'")
        XCTAssertFalse(weeklySummary.contains("T21:05:07Z"), "Unexpected raw UTC string in '\(weeklySummary)'")
    }

    func testRefreshIntervalToleranceSeconds() {
        XCTAssertEqual(RefreshIntervalOption.oneMinute.toleranceSeconds, 9)
        XCTAssertEqual(RefreshIntervalOption.fiveMinutes.toleranceSeconds, 45)
        XCTAssertEqual(RefreshIntervalOption.fifteenMinutes.toleranceSeconds, 60)
        XCTAssertEqual(RefreshIntervalOption.thirtyMinutes.toleranceSeconds, 60)
        XCTAssertNil(RefreshIntervalOption.manual.toleranceSeconds)
    }

    func testFetchSnapshotWithUtilityQoSExecutesBinary() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-agy-\(UUID().uuidString).sh")
        let scriptContents = """
        #!/bin/sh
        echo "Quota:"
        echo "Gemini Models          Five Hour Limit Remaining  88%   2026-11-14 18:05 PST"
        echo "Claude and GPT models  Weekly Limit Remaining     92%   2026-11-21 15:16 PST"
        """
        try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let result = try await AgyRunner().fetchSnapshot(
            customBinaryPath: scriptURL.path,
            timeoutSeconds: 5,
            qos: .utility
        )

        XCTAssertEqual(result.resolvedBinaryPath, scriptURL.path)
        XCTAssertEqual(result.snapshot.gemini?.fiveHour?.roundedPercent, 88)
        XCTAssertEqual(result.snapshot.thirdParty?.weekly?.roundedPercent, 92)
    }
}

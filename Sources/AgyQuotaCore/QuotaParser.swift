import Foundation

/// Errors raised when parsing `agy --print "/quota"` output.
public enum QuotaParserError: LocalizedError, Equatable {
    case emptyOutput
    case noQuotaEntriesFound(rawSnippet: String)

    public var errorDescription: String? {
        switch self {
        case .emptyOutput:
            return "Antigravity CLI returned empty output."
        case .noQuotaEntriesFound(let snippet):
            if snippet.isEmpty {
                return "No quota rows found in CLI output."
            }
            return "Could not parse quota entries from CLI output: \(snippet)"
        }
    }
}

/// Parses plain-text output from `agy --print "/quota"` into structured `QuotaSnapshot` data.
public enum QuotaParser {
    private static let ansiCSIRegex = try! NSRegularExpression(
        pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
        options: []
    )
    private static let ansiOSCRegex = try! NSRegularExpression(
        pattern: "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
        options: []
    )
    private static let primaryRowRegex = try! NSRegularExpression(
        pattern: #"^(.+?)\s{2,}(.+?)\s+(\d+(?:\.\d+)?)%(?:\s+(.+))?$"#,
        options: []
    )
    private static let fallbackRowRegex = try! NSRegularExpression(
        pattern: #"^(.+?)\s+((?:Weekly|Five[- ]Hour|5[- ]Hour|Daily|Hourly).*?)\s+(\d+(?:\.\d+)?)%(?:\s+(.+))?$"#,
        options: [.caseInsensitive]
    )

    private static let dateFormats = [
        "yyyy-MM-dd HH:mm zzz",
        "yyyy-MM-dd HH:mm zzzz",
        "yyyy-MM-dd HH:mm z",
        "yyyy-MM-dd HH:mm Z",
        "yyyy-MM-dd HH:mm"
    ]

    /// Removes ANSI CSI/OSC escape sequences and normalizes line endings.
    public static func stripANSI(_ input: String) -> String {
        var result = input.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        let csiRange = NSRange(result.startIndex..<result.endIndex, in: result)
        result = ansiCSIRegex.stringByReplacingMatches(in: result, options: [], range: csiRange, withTemplate: "")

        let oscRange = NSRange(result.startIndex..<result.endIndex, in: result)
        result = ansiOSCRegex.stringByReplacingMatches(in: result, options: [], range: oscRange, withTemplate: "")

        return result
    }

    /// Parses raw `agy --print "/quota"` text into a `QuotaSnapshot`.
    public static func parse(_ rawOutput: String, fetchedAt: Date = Date()) throws -> QuotaSnapshot {
        let cleaned = stripANSI(rawOutput)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw QuotaParserError.emptyOutput
        }

        var geminiTitle: String?
        var geminiWindows: [QuotaWindow] = []
        var thirdPartyTitle: String?
        var thirdPartyWindows: [QuotaWindow] = []

        for line in lines {
            if line.caseInsensitiveCompare("Quota:") == .orderedSame ||
               line.caseInsensitiveCompare("Quota") == .orderedSame {
                continue
            }

            guard let match = matchQuotaLine(line) else {
                continue
            }

            let category = classifyCategory(match.group)
            let windowKind = classifyWindowKind(match.windowLabel)
            let resetDate = match.resetText.flatMap(parseResetDate(_:))
            let window = QuotaWindow(
                kind: windowKind,
                rawLabel: match.windowLabel,
                remainingPercent: match.percent,
                rawResetText: match.resetText,
                resetDate: resetDate
            )

            switch category {
            case .gemini:
                if geminiTitle == nil {
                    geminiTitle = match.group
                }
                geminiWindows.append(window)
            case .thirdParty:
                if thirdPartyTitle == nil {
                    thirdPartyTitle = match.group
                }
                thirdPartyWindows.append(window)
            }
        }

        guard !geminiWindows.isEmpty || !thirdPartyWindows.isEmpty else {
            let snippet = lines.prefix(3).joined(separator: " | ")
            throw QuotaParserError.noQuotaEntriesFound(rawSnippet: String(snippet.prefix(160)))
        }

        let gemini = geminiWindows.isEmpty
            ? nil
            : CategoryQuota(
                category: .gemini,
                title: geminiTitle ?? QuotaCategory.gemini.defaultTitle,
                windows: geminiWindows
            )

        let thirdParty = thirdPartyWindows.isEmpty
            ? nil
            : CategoryQuota(
                category: .thirdParty,
                title: thirdPartyTitle ?? QuotaCategory.thirdParty.defaultTitle,
                windows: thirdPartyWindows
            )

        return QuotaSnapshot(
            gemini: gemini,
            thirdParty: thirdParty,
            fetchedAt: fetchedAt,
            rawOutput: cleaned
        )
    }

    private struct LineMatch {
        let group: String
        let windowLabel: String
        let percent: Double
        let resetText: String?
    }

    private static func matchQuotaLine(_ line: String) -> LineMatch? {
        for regex in [primaryRowRegex, fallbackRowRegex] {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
                  match.numberOfRanges >= 4,
                  let groupRange = Range(match.range(at: 1), in: line),
                  let labelRange = Range(match.range(at: 2), in: line),
                  let percentRange = Range(match.range(at: 3), in: line),
                  let percent = Double(line[percentRange]) else {
                continue
            }

            let group = String(line[groupRange]).trimmingCharacters(in: .whitespaces)
            let label = String(line[labelRange]).trimmingCharacters(in: .whitespaces)

            var resetText: String?
            if match.numberOfRanges >= 5,
               match.range(at: 4).location != NSNotFound,
               let resetRange = Range(match.range(at: 4), in: line) {
                let candidate = String(line[resetRange]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty {
                    resetText = candidate
                }
            }

            return LineMatch(
                group: group,
                windowLabel: label,
                percent: percent,
                resetText: resetText
            )
        }
        return nil
    }

    private static func classifyCategory(_ group: String) -> QuotaCategory {
        if group.localizedCaseInsensitiveContains("gemini") {
            return .gemini
        }
        return .thirdParty
    }

    private static func classifyWindowKind(_ label: String) -> QuotaWindowKind {
        let lower = label.lowercased()
        if lower.contains("five") || lower.contains("5-hour") || lower.contains("5 hour") || lower.contains("hour") {
            return .fiveHour
        }
        if lower.contains("week") {
            return .weekly
        }
        return .other(label)
    }

    /// Parses reset timestamps like `"2026-11-14 18:05 PST"` or ISO-8601 strings.
    public static func parseResetDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: trimmed) {
            return date
        }

        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        return isoStandard.date(from: trimmed)
    }
}

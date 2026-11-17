import Foundation

/// High-level model provider buckets displayed in the menu bar.
public enum QuotaCategory: String, Sendable, Equatable, CaseIterable {
    case gemini
    case thirdParty

    /// Short label used in compact text menu bar modes.
    public var shortLabel: String {
        switch self {
        case .gemini:
            return "G"
        case .thirdParty:
            return "3P"
        }
    }

    /// Single-letter identifier rendered inside ring-only menu bar icons.
    public var compactLetter: String {
        switch self {
        case .gemini:
            return "G"
        case .thirdParty:
            return "C"
        }
    }

    /// Default human-readable card title.
    public var defaultTitle: String {
        switch self {
        case .gemini:
            return "Gemini Models"
        case .thirdParty:
            return "Claude & GPT Models"
        }
    }
}

/// Time window classification for an individual quota line.
public enum QuotaWindowKind: Sendable, Equatable, Hashable {
    case fiveHour
    case weekly
    case other(String)

    public var displayTitle: String {
        switch self {
        case .fiveHour:
            return "5-Hour Limit"
        case .weekly:
            return "Weekly Limit"
        case .other(let label):
            return label
        }
    }

    public var sortOrder: Int {
        switch self {
        case .fiveHour:
            return 0
        case .weekly:
            return 1
        case .other:
            return 2
        }
    }
}

/// Visual representation style for the two menu bar indicators.
public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case ringsAndPercent
    case ringsOnly
    case numbersOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ringsAndPercent:
            return "Rings + %"
        case .ringsOnly:
            return "Rings"
        case .numbersOnly:
            return "Numbers"
        }
    }
}

/// Which quota metric drives the compact menu bar indicator per category.
public enum MenuBarMetric: String, CaseIterable, Identifiable, Sendable {
    case lowest
    case fiveHour
    case weekly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lowest:
            return "Lowest"
        case .fiveHour:
            return "5-Hour"
        case .weekly:
            return "Weekly"
        }
    }
}

/// Background polling cadence options configurable from the popover.
public enum RefreshIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case manual = 0

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .oneMinute:
            return "1 min"
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        case .manual:
            return "Manual"
        }
    }

    public var shortLabel: String {
        switch self {
        case .oneMinute:
            return "1m"
        case .fiveMinutes:
            return "5m"
        case .fifteenMinutes:
            return "15m"
        case .thirtyMinutes:
            return "30m"
        case .manual:
            return "Off"
        }
    }

    public var seconds: TimeInterval? {
        rawValue > 0 ? TimeInterval(rawValue) : nil
    }

    /// Timer leeway (15% of interval, capped at 60s) allowing macOS to coalesce wakeups.
    public var toleranceSeconds: TimeInterval? {
        guard let seconds else { return nil }
        return min(seconds * 0.15, 60)
    }
}

/// A single quota window (e.g., 5-Hour Limit or Weekly Limit) for a category.
public struct QuotaWindow: Sendable, Equatable, Identifiable {
    public let kind: QuotaWindowKind
    public let rawLabel: String
    public let remainingPercent: Double
    public let rawResetText: String?
    public let resetDate: Date?

    public var id: String {
        "\(kind.sortOrder)-\(rawLabel)"
    }

    public init(
        kind: QuotaWindowKind,
        rawLabel: String,
        remainingPercent: Double,
        rawResetText: String? = nil,
        resetDate: Date? = nil
    ) {
        self.kind = kind
        self.rawLabel = rawLabel
        self.remainingPercent = min(max(remainingPercent, 0.0), 100.0)
        self.rawResetText = rawResetText
        self.resetDate = resetDate
    }

    public var roundedPercent: Int {
        Int(remainingPercent.rounded())
    }

    public var fraction: Double {
        min(max(remainingPercent / 100.0, 0.0), 1.0)
    }

    /// Formats a human-readable countdown and reset timestamp relative to `now`.
    public func formattedResetSummary(
        relativeTo now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String? {
        if let resetDate {
            let interval = resetDate.timeIntervalSince(now)
            if interval <= 0 {
                return "Resetting soon"
            }

            let relative = Self.formatDuration(seconds: Int(interval))
            if let rawResetText, !rawResetText.isEmpty,
               let timeOnly = Self.extractTimeComponent(from: rawResetText) {
                let displayTimestamp = interval < 86_400 ? timeOnly : rawResetText
                return "Resets in \(relative) · \(displayTimestamp)"
            }

            let formatted = Self.formatLocalResetDate(
                resetDate,
                isWithinDay: interval < 86_400,
                timeZone: timeZone
            )
            return "Resets in \(relative) · \(formatted)"
        }

        if let rawResetText, !rawResetText.isEmpty {
            return "Resets \(rawResetText)"
        }

        return nil
    }

    private static func formatLocalResetDate(
        _ date: Date,
        isWithinDay: Bool,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = isWithinDay ? "h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private static func formatDuration(seconds totalSeconds: Int) -> String {
        if totalSeconds < 60 {
            return "< 1m"
        }
        let minutesTotal = totalSeconds / 60
        if minutesTotal < 60 {
            return "\(minutesTotal)m"
        }
        let hoursTotal = minutesTotal / 60
        let minutes = minutesTotal % 60
        if hoursTotal < 24 {
            return minutes > 0 ? "\(hoursTotal)h \(minutes)m" : "\(hoursTotal)h"
        }
        let days = hoursTotal / 24
        let hours = hoursTotal % 24
        return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
    }

    private static func extractTimeComponent(from rawResetText: String) -> String? {
        let trimmed = rawResetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 11 else { return nil }
        let prefix = String(trimmed.prefix(10))
        // Check if string begins with YYYY-MM-DD followed by space.
        let parts = prefix.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              trimmed.dropFirst(10).first == " " else {
            return nil
        }
        return String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
    }
}

/// Aggregated quota windows for either Gemini or Third-Party models.
public struct CategoryQuota: Sendable, Equatable {
    public let category: QuotaCategory
    public let title: String
    public let windows: [QuotaWindow]

    public init(category: QuotaCategory, title: String, windows: [QuotaWindow]) {
        self.category = category
        self.title = title
        self.windows = windows.sorted { lhs, rhs in
            if lhs.kind.sortOrder != rhs.kind.sortOrder {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.rawLabel.localizedCaseInsensitiveCompare(rhs.rawLabel) == .orderedAscending
        }
    }

    public var fiveHour: QuotaWindow? {
        windows.first { $0.kind == .fiveHour }
    }

    public var weekly: QuotaWindow? {
        windows.first { $0.kind == .weekly }
    }

    public var lowestWindow: QuotaWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    /// Returns the rounded percentage to display in the menu bar for the selected metric.
    public func percent(for metric: MenuBarMetric) -> Int? {
        switch metric {
        case .lowest:
            return lowestWindow?.roundedPercent
        case .fiveHour:
            return (fiveHour ?? lowestWindow)?.roundedPercent
        case .weekly:
            return (weekly ?? lowestWindow)?.roundedPercent
        }
    }
}

/// Full parsed quota snapshot returned from a single `agy --print "/quota"` invocation.
public struct QuotaSnapshot: Sendable, Equatable {
    public let gemini: CategoryQuota?
    public let thirdParty: CategoryQuota?
    public let fetchedAt: Date
    public let rawOutput: String

    public init(
        gemini: CategoryQuota?,
        thirdParty: CategoryQuota?,
        fetchedAt: Date = Date(),
        rawOutput: String
    ) {
        self.gemini = gemini
        self.thirdParty = thirdParty
        self.fetchedAt = fetchedAt
        self.rawOutput = rawOutput
    }
}

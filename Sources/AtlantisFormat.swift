//
//  AtlantisFormat.swift
//  atlantis
//

import Foundation

/// Shared byte/duration/time formatting. Headless — no SwiftUI import.
enum AtlantisFormat {
    static func duration(startAt: TimeInterval, endAt: TimeInterval?) -> String {
        guard let endAt = endAt else { return "…" }
        let seconds = endAt - startAt
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }

    static func bytes(_ count: Int) -> String {
        let units = ["B", "KB", "MB"]
        var value = Double(count)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(count) \(units[0])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func time(_ startAt: TimeInterval) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: startAt))
    }

    /// `m:ss` under an hour, `h:mm:ss` at or above. Truncates, never rounds.
    /// Negative input clamps to zero (Request Overview §3.5 / §7).
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Same formatting as `duration(startAt:endAt:)` but for an in-flight package —
    /// takes `now` instead of a completed `endAt`, and clamps negative deltas to zero.
    static func elapsed(startAt: TimeInterval, now: TimeInterval) -> String {
        let seconds = max(0, now - startAt)
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }

    /// `Today H:mm:ss.SSS` / `Yesterday H:mm:ss.SSS` / `yyyy-MM-dd HH:mm:ss.SSS`,
    /// compared against `now` in `timeZone` calendar days (Request Overview §5).
    static func started(_ startAt: TimeInterval, now: TimeInterval, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = Date(timeIntervalSince1970: startAt)
        let nowDate = Date(timeIntervalSince1970: now)
        let startDay = calendar.startOfDay(for: startDate)
        let nowDay = calendar.startOfDay(for: nowDate)
        let dayDiff = calendar.dateComponents([.day], from: startDay, to: nowDay).day ?? 0

        let timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeOnlyFormatter.timeZone = timeZone
        timeOnlyFormatter.dateFormat = "H:mm:ss.SSS"

        switch dayDiff {
        case 0:
            return "Today " + timeOnlyFormatter.string(from: startDate)
        case 1:
            return "Yesterday " + timeOnlyFormatter.string(from: startDate)
        default:
            let fullFormatter = DateFormatter()
            fullFormatter.locale = Locale(identifier: "en_US_POSIX")
            fullFormatter.timeZone = timeZone
            fullFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return fullFormatter.string(from: startDate)
        }
    }
}

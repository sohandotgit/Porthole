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
}

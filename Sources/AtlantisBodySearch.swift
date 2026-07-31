//
//  AtlantisBodySearch.swift
//  atlantis
//

import Foundation

/// Case-insensitive in-body search, shared by the detail view sections and the
/// headless test target.
public enum AtlantisBodySearch {

    /// Case-insensitive, all non-overlapping ranges of `query` within `text`.
    /// Empty/whitespace query ⇒ []. Returned in ascending order.
    public static func matchRanges(in text: String, query: String) -> [Range<String.Index>] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: trimmed, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            ranges.append(found)
            searchStart = found.upperBound
        }
        return ranges
    }

    /// Convenience: number of matches. == matchRanges(...).count.
    public static func matchCount(in text: String, query: String) -> Int {
        matchRanges(in: text, query: query).count
    }

    /// Case-insensitive, all non-overlapping `NSRange`s of `query` within `text`,
    /// ascending. Query is trimmed before matching; empty/whitespace ⇒ `[]`.
    static func nsMatchRanges(in text: String, query: String) -> [NSRange] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let haystack = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let found = haystack.range(of: trimmed, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextLocation = found.location + found.length
            searchRange = NSRange(location: nextLocation, length: haystack.length - nextLocation)
        }
        return ranges
    }
}

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
}

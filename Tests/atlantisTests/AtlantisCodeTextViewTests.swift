//
//  AtlantisCodeTextViewTests.swift
//  atlantis
//
//  body-viewer.spec.md §10.5-10.6 — smoke only, no rendering assertions.
//

import Foundation
import XCTest
#if canImport(SwiftUI)
import SwiftUI

@testable import Atlantis

@available(iOS 15.0, macOS 12.0, *)
final class AtlantisCodeTextViewTests: XCTestCase {

    func test10_5_buildsWithEmptyAttributedString() {
        let view = AtlantisCodeTextView(attributed: NSAttributedString(string: ""), lineStarts: [0])
        _ = view.body
    }

    func test10_6_buildsWithNilAndNonNilCurrentMatchRange() {
        let text = "hello world"
        let attributed = NSAttributedString(string: text)
        let lineStarts = [0]

        let withoutMatch = AtlantisCodeTextView(attributed: attributed, lineStarts: lineStarts,
                                                  matchRanges: [], currentMatchRange: nil)
        _ = withoutMatch.body

        let matchRange = NSRange(location: 0, length: 5)
        let withMatch = AtlantisCodeTextView(attributed: attributed, lineStarts: lineStarts,
                                               matchRanges: [matchRange], currentMatchRange: matchRange)
        _ = withMatch.body
    }

    /// B5-6: the line-numbers gutter toggle is a real, wired parameter.
    func test10_showsLineNumbersTogglesWithoutTrapping() {
        let attributed = NSAttributedString(string: "line one\nline two")
        let hidden = AtlantisCodeTextView(attributed: attributed, lineStarts: [0, 9], showsLineNumbers: false)
        _ = hidden.body
        let shown = AtlantisCodeTextView(attributed: attributed, lineStarts: [0, 9], showsLineNumbers: true)
        _ = shown.body
    }

    /// B4-1: changing the match set while a current match is set must not trap
    /// and must not leave the representable pointing at a stale range — this is
    /// a smoke check only; the highlight-clearing logic itself lives in a
    /// private free function this test target cannot reach directly.
    func test10_matchSetChangeWithDifferentCurrentRangeDoesNotTrap() {
        let text = "alpha beta alpha beta alpha"
        let attributed = NSAttributedString(string: text)
        let lineStarts = [0]
        let firstMatches = [NSRange(location: 0, length: 5), NSRange(location: 11, length: 5)]
        let view1 = AtlantisCodeTextView(attributed: attributed, lineStarts: lineStarts,
                                          matchRanges: firstMatches, currentMatchRange: firstMatches[0])
        _ = view1.body

        // Simulates a query change: a disjoint match set with a new current range.
        let secondMatches = [NSRange(location: 17, length: 5)]
        let view2 = AtlantisCodeTextView(attributed: attributed, lineStarts: lineStarts,
                                          matchRanges: secondMatches, currentMatchRange: secondMatches[0])
        _ = view2.body
    }
}
#endif

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
@MainActor
private func atlantisCompleteStream(_ text: String) -> AtlantisBodyStream {
    let attributed = NSAttributedString(string: text)
    let lineStarts = AtlantisSyntaxHighlighter.lineStarts(in: text)
    let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
    for chunk in AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts) {
        stream.append(chunk)
    }
    stream.markComplete()
    return stream
}

@available(iOS 15.0, macOS 12.0, *)
@MainActor
final class AtlantisCodeTextViewTests: XCTestCase {

    func test10_5_buildsWithEmptyAttributedString() {
        let stream = atlantisCompleteStream("")
        let view = AtlantisCodeTextView(stream: stream, version: stream.version)
        _ = view.body
    }

    func test10_6_buildsWithNilAndNonNilCurrentMatchRange() {
        let text = "hello world"
        let stream = atlantisCompleteStream(text)

        let withoutMatch = AtlantisCodeTextView(stream: stream, version: stream.version,
                                                  matchRanges: [], currentMatchRange: nil)
        _ = withoutMatch.body

        let matchRange = NSRange(location: 0, length: 5)
        let withMatch = AtlantisCodeTextView(stream: stream, version: stream.version,
                                               matchRanges: [matchRange], currentMatchRange: matchRange)
        _ = withMatch.body
    }

    /// B5-6: the line-numbers gutter toggle is a real, wired parameter.
    func test10_showsLineNumbersTogglesWithoutTrapping() {
        let stream = atlantisCompleteStream("line one\nline two")
        let hidden = AtlantisCodeTextView(stream: stream, version: stream.version, showsLineNumbers: false)
        _ = hidden.body
        let shown = AtlantisCodeTextView(stream: stream, version: stream.version, showsLineNumbers: true)
        _ = shown.body
    }

    /// B4-1: changing the match set while a current match is set must not trap
    /// and must not leave the representable pointing at a stale range — this is
    /// a smoke check only; the highlight-clearing logic itself lives in a
    /// private free function this test target cannot reach directly.
    func test10_matchSetChangeWithDifferentCurrentRangeDoesNotTrap() {
        let text = "alpha beta alpha beta alpha"
        let stream = atlantisCompleteStream(text)
        let firstMatches = [NSRange(location: 0, length: 5), NSRange(location: 11, length: 5)]
        let view1 = AtlantisCodeTextView(stream: stream, version: stream.version,
                                          matchRanges: firstMatches, currentMatchRange: firstMatches[0])
        _ = view1.body

        // Simulates a query change: a disjoint match set with a new current range.
        let secondMatches = [NSRange(location: 17, length: 5)]
        let view2 = AtlantisCodeTextView(stream: stream, version: stream.version,
                                          matchRanges: secondMatches, currentMatchRange: secondMatches[0])
        _ = view2.body
    }

    /// docs/plan-progressive-body-render.md Part 2 — a mid-stream (incomplete)
    /// version below the stream's current chunk count still builds a valid
    /// view; the representable applies only chunks `0..<version`.
    func test10_buildsWithPartialVersionDuringStreaming() {
        let text = Array(repeating: "line\n", count: 5_000).joined()
        let attributed = NSAttributedString(string: text)
        let lineStarts = AtlantisSyntaxHighlighter.lineStarts(in: text)
        let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertGreaterThan(chunks.count, 1)
        stream.append(chunks[0])
        let view = AtlantisCodeTextView(stream: stream, version: stream.version)
        _ = view.body
    }
}
#endif

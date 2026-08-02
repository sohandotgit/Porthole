//
//  AtlantisBodyStreamTests.swift
//  atlantis
//
//  docs/plan-progressive-body-render.md Part 1/§Tests — chunk alignment,
//  lineStarts continuity, cancellation (partial-stream), and streaming search
//  scoping.
//

import Foundation
import XCTest
#if canImport(SwiftUI)
@testable import Atlantis

@available(iOS 15.0, macOS 12.0, *)
@MainActor
final class AtlantisBodyStreamTests: XCTestCase {

    private func makeAttributedAndLineStarts(_ text: String) -> (NSAttributedString, [Int]) {
        (NSAttributedString(string: text), AtlantisSyntaxHighlighter.lineStarts(in: text))
    }

    /// Chunk boundaries always land on `\n`; concatenated chunks reproduce the
    /// full text exactly.
    func testChunkBoundariesAlwaysLandOnNewlineAndConcatenateToFullText() {
        let text = (0..<10_000).map { "line \($0)" }.joined(separator: "\n")
        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertGreaterThan(chunks.count, 1, "fixture must be large enough to force multiple chunks")

        var reassembled = ""
        for chunk in chunks {
            let s = chunk.attributed.string
            if !s.isEmpty && chunk.attributed !== chunks.last?.attributed {
                XCTAssertTrue(s.hasSuffix("\n"), "every non-final chunk must end at a line boundary")
            }
            reassembled += s
        }
        XCTAssertEqual(reassembled, text)
    }

    /// A single tiny (sub-chunk-size) body produces exactly one chunk — no
    /// second streaming code path to maintain (Open decision 2).
    func testSmallBodyProducesExactlyOneChunk() {
        let text = "{\"a\":1}"
        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].attributed.string, text)
    }

    func testEmptyTextProducesNoChunks() {
        let (attributed, lineStarts) = makeAttributedAndLineStarts("")
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertEqual(chunks.count, 0)
    }

    /// `stream.lineStarts` after chunk *n* == `lineStarts(fullText)` prefix
    /// through that chunk's last line.
    func testLineStartsAfterEachChunkIsAPrefixOfTheFullLineStarts() {
        let text = (0..<10_000).map { "line \($0)" }.joined(separator: "\n")
        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let fullLineStarts = lineStarts
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: fullLineStarts)
        XCTAssertGreaterThan(chunks.count, 1)

        let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
        var consumedLines = 0
        for chunk in chunks {
            stream.append(chunk)
            consumedLines += chunk.lineStarts.count
            XCTAssertEqual(stream.lineStarts, Array(fullLineStarts.prefix(consumedLines)))
        }
        XCTAssertEqual(stream.lineStarts, fullLineStarts)
    }

    /// Cancel mid-stream (simulated: the producer simply stops appending and
    /// never calls `markComplete`) → the stream is left partial and
    /// `isComplete` stays false, mirroring `streamIfNeeded`'s cancellation
    /// branch which drops the stream (`stream = nil`) instead of caching it.
    func testPartialStreamNeverMarkedComplete() {
        let text = (0..<10_000).map { "line \($0)" }.joined(separator: "\n")
        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertGreaterThan(chunks.count, 2)

        let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
        stream.append(chunks[0])
        // Cancellation happens here — the producer never reaches markComplete().
        XCTAssertFalse(stream.isComplete)
        XCTAssertEqual(stream.version, 1)
        XCTAssertLessThan(stream.loadedUTF16, attributed.length)
    }

    /// Search during streaming must be scoped to `loadedText` — matches
    /// beyond what has actually landed would point `AtlantisCodeTextView` at
    /// ranges TextKit hasn't laid out yet.
    func testSearchDuringStreamingIsScopedToLoadedTextOnly() {
        // "needle" appears once early (inside chunk 0) and once late (well
        // past chunk 0) — force multiple chunks with padding lines.
        var lines: [String] = ["needle at the top"]
        lines.append(contentsOf: (0..<10_000).map { "padding \($0)" })
        lines.append("needle at the bottom")
        let text = lines.joined(separator: "\n")

        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        XCTAssertGreaterThan(chunks.count, 1)

        let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
        stream.append(chunks[0])

        let midStreamMatches = AtlantisBodySearch.nsMatchRanges(in: stream.loadedText, query: "needle")
        XCTAssertEqual(midStreamMatches.count, 1, "only the top occurrence has streamed in so far")

        for chunk in chunks.dropFirst() { stream.append(chunk) }
        stream.markComplete()
        let completeMatches = AtlantisBodySearch.nsMatchRanges(in: stream.loadedText, query: "needle")
        XCTAssertEqual(completeMatches.count, 2)
        XCTAssertEqual(stream.loadedText, text)
    }

    /// Mode switch back to a completed stream is served with `version`
    /// already at its final value — `AtlantisCodeTextView` applies every
    /// chunk in one pass with no further streaming.
    func testCompletedStreamVersionEqualsChunkCount() {
        let text = (0..<5_000).map { "line \($0)" }.joined(separator: "\n")
        let (attributed, lineStarts) = makeAttributedAndLineStarts(text)
        let chunks = AtlantisBodyStream.makeChunks(attributed: attributed, lineStarts: lineStarts)
        let stream = AtlantisBodyStream(fullText: text, totalUTF16: attributed.length)
        for chunk in chunks { stream.append(chunk) }
        stream.markComplete()

        XCTAssertTrue(stream.isComplete)
        XCTAssertEqual(stream.version, chunks.count)
        XCTAssertEqual(stream.loadedText, text)
        XCTAssertEqual(stream.loadedUTF16, attributed.length)
    }
}
#endif

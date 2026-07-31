//
//  AtlantisBodyHighlighterTests.swift
//  atlantis
//
//  Tests/body-viewer.spec.md §1-3 — AtlantisSyntaxHighlighter (JSON, XML/HTML, lineStarts).
//

import Foundation
import XCTest
@testable import Atlantis

private func tokens(_ s: String) -> [AtlantisToken] {
    AtlantisSyntaxHighlighter.jsonTokens(in: Array(s.utf16))
}

private func kinds(_ s: String) -> [AtlantisTokenKind] {
    tokens(s).map { $0.kind }
}

private func xmlTokens(_ s: String) -> [AtlantisToken] {
    AtlantisSyntaxHighlighter.xmlTokens(in: Array(s.utf16))
}

// MARK: - 1. JSON

final class AtlantisJSONHighlighterTests: XCTestCase {

    func test1_1_keyVsStringValue() {
        let t = tokens(#"{"a":"b"}"#)
        let key = t.first { $0.kind == .key }
        let str = t.first { $0.kind == .string }
        XCTAssertEqual(key?.range, NSRange(location: 1, length: 3))
        XCTAssertEqual(str?.range, NSRange(location: 5, length: 3))
    }

    func test1_2_whitespaceBeforeColonStillMarksKey() {
        let t = tokens(#"{"a" : 1}"#)
        XCTAssertTrue(t.contains { $0.kind == .key && $0.range == NSRange(location: 1, length: 3) })
    }

    func test1_3_escapedQuoteDoesNotEndString() {
        // Raw literal: {"a":"x\"y"} — value string is `"x\"y"`, 6 UTF-16 units
        // (quote, x, backslash, quote, y, quote), closing at the real quote.
        let s = #"{"a":"x\"y"}"#
        let t = tokens(s)
        let strings = t.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings.first?.range, NSRange(location: 5, length: 6))
    }

    func test1_4_escapedBackslashBeforeClosingQuote() {
        // Raw literal: {"a":"x\\"} — value string is `"x\\"` (an escaped
        // backslash), 5 UTF-16 units, closing at the real quote; the following
        // `}` is separate punctuation.
        let s = #"{"a":"x\\"}"#
        let t = tokens(s)
        let strings = t.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        guard let value = strings.first else { return XCTFail("no string token") }
        XCTAssertEqual(value.range, NSRange(location: 5, length: 5))
        let closeBrace = NSMaxRange(value.range)
        let punctuationAfter = t.first { $0.kind == .punctuation && $0.range.location == closeBrace }
        XCTAssertNotNil(punctuationAfter)
        XCTAssertEqual(NSMaxRange(punctuationAfter!.range), (s as NSString).length)
    }

    func test1_5_numbers() {
        let t = tokens("[1,-2,3.5,1e10,-2.5E-3]")
        let numbers = t.filter { $0.kind == .number }
        XCTAssertEqual(numbers.map { $0.range.length }, [1, 2, 3, 4, 7])
        XCTAssertEqual(numbers.map { $0.range.location }, [1, 3, 6, 10, 15])
    }

    func test1_6_literals() {
        let t = tokens("[true,false,null]")
        let literals = t.filter { $0.kind == .literal }
        XCTAssertEqual(literals.map { $0.range.length }, [4, 5, 4])
        XCTAssertEqual(literals.map { $0.range.location }, [1, 6, 12])
    }

    func test1_7_nullPrefixedKeyIsNotALiteral() {
        let t = tokens(#"{"nullable":1}"#)
        XCTAssertEqual(t.filter { $0.kind == .literal }.count, 0)
    }

    func test1_8_punctuationCoalescing() {
        let t = tokens("{ \"a\" : [ 1 ] }")
        XCTAssertLessThan(t.count, 8)
    }

    func test1_9_unterminatedStringDoesNotHangOrTrap() {
        let s = #"{"a":"unclosed"#
        let t = tokens(s)
        XCTAssertEqual(t.last?.kind, .string)
        XCTAssertEqual(NSMaxRange(t.last!.range), (s as NSString).length)
        XCTAssertEqual((s as NSString).length, 14)
    }

    func test1_10_emptyInput() {
        XCTAssertEqual(tokens(""), [])
    }

    func test1_11_nonASCIIKeepsUTF16OffsetsValid() {
        let s = #"{"emoji":"🙂","n":1}"#
        let t = tokens(s)
        let nsLength = (s as NSString).length
        for token in t {
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), nsLength)
        }
        let attributed = AtlantisSyntaxHighlighter.attributedString(
            text: s,
            tokens: t,
            font: AtlantisSyntaxTheme.canvasFont,
            paragraphStyle: AtlantisSyntaxTheme.noWrapParagraphStyle)
        XCTAssertEqual(attributed.length, nsLength)
    }

    func test1_12_noOverlappingOrOutOfOrderRanges() {
        var fixture = "{\n"
        for i in 0..<50 {
            fixture += "  \"key\(i)\": \(i),\n"
        }
        fixture += "  \"done\": true\n}"
        let t = tokens(fixture)
        var previousEnd = 0
        for token in t {
            XCTAssertGreaterThanOrEqual(token.range.location, previousEnd)
            previousEnd = NSMaxRange(token.range)
        }
    }

    func test1_13_tokenizerEmitsNSRangeFromUInt16Buffer() {
        let buffer: [UInt16] = Array("{\"a\":1}".utf16)
        let t = AtlantisSyntaxHighlighter.jsonTokens(in: buffer)
        XCTAssertFalse(t.isEmpty)
        for token in t {
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), buffer.count)
        }
    }
}

// MARK: - 2. XML / HTML

final class AtlantisXMLHighlighterTests: XCTestCase {

    func test2_1_elementAndAttribute() {
        let s = #"<a href="x">t</a>"#
        let t = xmlTokens(s)
        let tagNames = t.filter { $0.kind == .tagName }
        XCTAssertEqual(tagNames.map { $0.range }, [NSRange(location: 1, length: 1), NSRange(location: 15, length: 1)])
        let attrName = t.first { $0.kind == .attrName }
        XCTAssertEqual(attrName?.range, NSRange(location: 3, length: 4))
        let attrValue = t.first { $0.kind == .attrValue }
        XCTAssertEqual(attrValue?.range, NSRange(location: 8, length: 3))
    }

    func test2_2_singleQuotedAttribute() {
        let s = "<a b='c'>"
        let t = xmlTokens(s)
        let attrValues = t.filter { $0.kind == .attrValue }
        XCTAssertEqual(attrValues.count, 1)
        XCTAssertEqual(attrValues.first?.range.length, 3)
    }

    func test2_3_comment() {
        let s = "<!-- hi --><a/>"
        let t = xmlTokens(s)
        let comments = t.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments.first?.range, NSRange(location: 0, length: 11))
    }

    func test2_4_doctype() {
        let s = "<!DOCTYPE html><a/>"
        let t = xmlTokens(s)
        let comments = t.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments.first?.range, NSRange(location: 0, length: 15))
    }

    func test2_5_selfClosing() {
        let s = #"<a b="c"/>"#
        let t = xmlTokens(s)
        XCTAssertFalse(t.isEmpty)
        let slashIndex = (s as NSString).range(of: "/").location
        XCTAssertFalse(t.contains { $0.kind == .attrName && $0.range.location == slashIndex })
    }

    func test2_6_malformedInputDoesNotTrap() {
        let nsLength: (String) -> Int = { ($0 as NSString).length }
        for s in [#"<a b="unclosed"#, "<", "</>", "<<a>>"] {
            let t = xmlTokens(s)
            for token in t {
                XCTAssertGreaterThanOrEqual(token.range.location, 0)
                XCTAssertLessThanOrEqual(NSMaxRange(token.range), nsLength(s))
            }
        }
    }

    func test2_7_textContentIsNotColored() {
        let t = xmlTokens("<a>hello</a>")
        let textRange = NSRange(location: 3, length: 5)
        for token in t {
            XCTAssertEqual(NSIntersectionRange(token.range, textRange).length, 0)
        }
    }
}

// MARK: - 3. lineStarts

final class AtlantisLineStartsTests: XCTestCase {

    func test3_1_basic() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "a\nb\nc"), [0, 2, 4])
    }

    func test3_2_trailingNewlineAddsNoPhantomLine() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "a\n"), [0])
    }

    func test3_3_empty() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: ""), [0])
    }

    func test3_4_blankLines() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "\n\n"), [0, 1])
    }

    func test3_5_crlf() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "a\r\nb"), [0, 3])
    }

    func test3_6_twentyLineFixture() {
        let lines = (0..<20).map { "line\($0)" }
        let fixture = lines.joined(separator: "\n")
        let expectedCount = fixture.components(separatedBy: "\n").count
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: fixture).count, expectedCount)
    }

    func test3_7_lineCountContractUsedByStatsLine() {
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "").count, 1)
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "a\n").count, 1)
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: "a\nb").count, 2)
    }
}

// MARK: - 10.8 / 10.9 theme presence (owned here since AtlantisSyntaxTheme is B2)

final class AtlantisSyntaxThemeTests: XCTestCase {

    func test10_8_colorForEveryTokenKind() {
        let kinds: [AtlantisTokenKind] = [
            .key, .string, .number, .literal, .punctuation, .plain,
            .tagName, .attrName, .attrValue, .comment,
            .hexOffset, .hexBytes, .hexAscii
        ]
        for kind in kinds {
            _ = AtlantisSyntaxTheme.color(for: kind)
        }
    }

    func test10_9_everyTokenMemberIsPresent() {
        _ = AtlantisSyntaxTheme.matchBackground
        _ = AtlantisSyntaxTheme.currentMatchBackground
        _ = AtlantisSyntaxTheme.currentMatchRing
        _ = AtlantisSyntaxTheme.currentMatchForeground
        _ = AtlantisSyntaxTheme.currentRowTint
        _ = AtlantisSyntaxTheme.currentMatchMarker
        _ = AtlantisSyntaxTheme.pageFill
        _ = AtlantisSyntaxTheme.cardFill
        _ = AtlantisSyntaxTheme.gutterFill
        _ = AtlantisSyntaxTheme.gutterDivider
        _ = AtlantisSyntaxTheme.gutterText
        _ = AtlantisSyntaxTheme.gutterTextCurrent
        _ = AtlantisSyntaxTheme.accent
        _ = AtlantisSyntaxTheme.accentFill
        _ = AtlantisSyntaxTheme.neutralFill
        _ = AtlantisSyntaxTheme.controlTrackFill
        _ = AtlantisSyntaxTheme.segmentSelectedFill
        _ = AtlantisSyntaxTheme.segmentSelectedLabel
        _ = AtlantisSyntaxTheme.segmentLabel
        _ = AtlantisSyntaxTheme.segmentLabelDisabled
        _ = AtlantisSyntaxTheme.chipGlyphInactive
        _ = AtlantisSyntaxTheme.divider
        _ = AtlantisSyntaxTheme.labelPrimary
        _ = AtlantisSyntaxTheme.labelHeading
        _ = AtlantisSyntaxTheme.labelSecondary
        _ = AtlantisSyntaxTheme.labelTertiary
        _ = AtlantisSyntaxTheme.labelQuaternary
        _ = AtlantisSyntaxTheme.labelDisabled
        _ = AtlantisSyntaxTheme.searchCaret
        _ = AtlantisSyntaxTheme.searchGlyph
        _ = AtlantisSyntaxTheme.searchQueryText
        _ = AtlantisSyntaxTheme.counterText
        _ = AtlantisSyntaxTheme.badgeJSONForeground
        _ = AtlantisSyntaxTheme.badgeJSONFill
        _ = AtlantisSyntaxTheme.badgeBinaryForeground
        _ = AtlantisSyntaxTheme.badgeBinaryFill
        _ = AtlantisSyntaxTheme.badgeXMLForeground
        _ = AtlantisSyntaxTheme.badgeXMLFill
        _ = AtlantisSyntaxTheme.badgeHTMLForeground
        _ = AtlantisSyntaxTheme.badgeHTMLFill
        _ = AtlantisSyntaxTheme.badgeFormForeground
        _ = AtlantisSyntaxTheme.badgeFormFill
        _ = AtlantisSyntaxTheme.badgeImageForeground
        _ = AtlantisSyntaxTheme.badgeImageFill
        _ = AtlantisSyntaxTheme.badgeTextForeground
        _ = AtlantisSyntaxTheme.badgeTextFill
        _ = AtlantisSyntaxTheme.warnTileFill
        _ = AtlantisSyntaxTheme.warnGlyph
        _ = AtlantisSyntaxTheme.bannerFill
        _ = AtlantisSyntaxTheme.bannerText
    }
}

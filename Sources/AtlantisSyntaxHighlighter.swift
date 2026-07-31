//
//  AtlantisSyntaxHighlighter.swift
//  atlantis
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One colored range in a tokenized body. `range` indexes the UTF-16 buffer the
/// tokenizer scanned, so it is safe to hand directly to `NSAttributedString` /
/// `NSMutableAttributedString` without any `String.Index` conversion.
struct AtlantisToken: Equatable {
    let kind: AtlantisTokenKind
    let range: NSRange
}

/// Token kinds, a JSON tokenizer, an XML/HTML tokenizer, a `lineStarts` table, and
/// the `NSAttributedString` builder. Scans a `[UInt16]` UTF-16 buffer directly and
/// emits `NSRange` — no `String.Index`<->`AttributedString` conversion in any loop
/// (perf contract rule 7). Headless: does not import SwiftUI or any UI framework.
enum AtlantisSyntaxHighlighter {

    // MARK: - ASCII constants (UTF-16 code units)

    private static let quote: UInt16 = 0x22        // "
    private static let singleQuote: UInt16 = 0x27   // '
    private static let backslash: UInt16 = 0x5C     // \
    private static let colon: UInt16 = 0x3A         // :
    private static let minus: UInt16 = 0x2D         // -
    private static let plus: UInt16 = 0x2B          // +
    private static let dot: UInt16 = 0x2E           // .
    private static let lt: UInt16 = 0x3C            // <
    private static let gt: UInt16 = 0x3E            // >
    private static let slash: UInt16 = 0x2F         // /
    private static let bang: UInt16 = 0x21           // !
    private static let equalsSign: UInt16 = 0x3D    // =
    private static let dash: UInt16 = 0x2D           // -

    private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isAlpha(_ c: UInt16) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }
    private static func isWhitespace(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }
    private static func isIdentifierStart(_ c: UInt16) -> Bool { isAlpha(c) || c == 0x5F }
    private static func isIdentifierChar(_ c: UInt16) -> Bool {
        isAlpha(c) || isDigit(c) || c == 0x5F || c == dash || c == colon
    }

    // MARK: - JSON

    /// Tokenizes a JSON body. Exhaustive over string/number/literal/punctuation;
    /// strings that are immediately followed (across whitespace) by `:` are
    /// reclassified as `.key`.
    static func jsonTokens(in buffer: [UInt16]) -> [AtlantisToken] {
        let n = buffer.count
        var tokens: [AtlantisToken] = []
        var i = 0
        var punctuationStart: Int? = nil

        func flushPunctuation(upTo end: Int) {
            if let start = punctuationStart, end > start {
                tokens.append(AtlantisToken(kind: .punctuation, range: NSRange(location: start, length: end - start)))
            }
            punctuationStart = nil
        }

        while i < n {
            let c = buffer[i]

            if c == quote {
                flushPunctuation(upTo: i)
                let start = i
                i += 1
                var escaped = false
                while i < n {
                    let cc = buffer[i]
                    if escaped {
                        escaped = false
                        i += 1
                        continue
                    }
                    if cc == backslash {
                        escaped = true
                        i += 1
                        continue
                    }
                    if cc == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                var kind: AtlantisTokenKind = .string
                var lookahead = i
                while lookahead < n && isWhitespace(buffer[lookahead]) { lookahead += 1 }
                if lookahead < n && buffer[lookahead] == colon { kind = .key }
                tokens.append(AtlantisToken(kind: kind, range: NSRange(location: start, length: i - start)))
                continue
            }

            if isDigit(c) || (c == minus && i + 1 < n && isDigit(buffer[i + 1])) {
                flushPunctuation(upTo: i)
                let start = i
                if c == minus { i += 1 }
                while i < n && isDigit(buffer[i]) { i += 1 }
                if i < n && buffer[i] == dot && i + 1 < n && isDigit(buffer[i + 1]) {
                    i += 1
                    while i < n && isDigit(buffer[i]) { i += 1 }
                }
                if i < n && (buffer[i] == 0x65 || buffer[i] == 0x45) { // e/E
                    var j = i + 1
                    if j < n && (buffer[j] == plus || buffer[j] == minus) { j += 1 }
                    if j < n && isDigit(buffer[j]) {
                        i = j
                        while i < n && isDigit(buffer[i]) { i += 1 }
                    }
                }
                tokens.append(AtlantisToken(kind: .number, range: NSRange(location: start, length: i - start)))
                continue
            }

            if isIdentifierStart(c), let literal = matchLiteral(buffer, at: i, n: n) {
                flushPunctuation(upTo: i)
                tokens.append(AtlantisToken(kind: .literal, range: NSRange(location: i, length: literal)))
                i += literal
                continue
            }

            if punctuationStart == nil { punctuationStart = i }
            i += 1
        }

        flushPunctuation(upTo: n)
        return tokens
    }

    private static let trueChars: [UInt16] = Array("true".utf16)
    private static let falseChars: [UInt16] = Array("false".utf16)
    private static let nullChars: [UInt16] = Array("null".utf16)

    private static func matchLiteral(_ buffer: [UInt16], at i: Int, n: Int) -> Int? {
        for candidate in [trueChars, falseChars, nullChars] {
            let len = candidate.count
            guard i + len <= n else { continue }
            var matches = true
            for k in 0..<len where buffer[i + k] != candidate[k] {
                matches = false
                break
            }
            guard matches else { continue }
            let after = i + len
            if after < n && isIdentifierChar(buffer[after]) { continue }
            return len
        }
        return nil
    }

    // MARK: - XML / HTML

    /// Tokenizes XML/HTML markup: tag names, attribute names, attribute values
    /// (quotes included), and comments (`<!-- ... -->` and `<!DOCTYPE ...>`).
    /// Text content between tags is never tokenized.
    static func xmlTokens(in buffer: [UInt16]) -> [AtlantisToken] {
        let n = buffer.count
        var tokens: [AtlantisToken] = []
        var i = 0

        while i < n {
            guard buffer[i] == lt else { i += 1; continue }
            let tagStart = i

            if i + 3 < n, buffer[i + 1] == bang, buffer[i + 2] == dash, buffer[i + 3] == dash {
                // Comment: <!-- ... -->
                var j = i + 4
                var closed = false
                while j + 2 < n {
                    if buffer[j] == dash, buffer[j + 1] == dash, buffer[j + 2] == gt {
                        j += 3
                        closed = true
                        break
                    }
                    j += 1
                }
                if !closed { j = n }
                tokens.append(AtlantisToken(kind: .comment, range: NSRange(location: tagStart, length: j - tagStart)))
                i = j
                continue
            }

            if i + 1 < n, buffer[i + 1] == bang {
                // Doctype or other markup declaration: <! ... >
                var j = i + 2
                while j < n && buffer[j] != gt { j += 1 }
                if j < n { j += 1 }
                tokens.append(AtlantisToken(kind: .comment, range: NSRange(location: tagStart, length: j - tagStart)))
                i = j
                continue
            }

            // Regular / closing tag.
            var j = i + 1
            if j < n && buffer[j] == slash { j += 1 }

            if j < n && isIdentifierStart(buffer[j]) {
                let nameStart = j
                while j < n && isIdentifierChar(buffer[j]) { j += 1 }
                tokens.append(AtlantisToken(kind: .tagName, range: NSRange(location: nameStart, length: j - nameStart)))
            }

            // Attributes until the tag's closing '>'.
            while j < n && buffer[j] != gt {
                let c = buffer[j]
                if isWhitespace(c) { j += 1; continue }
                if c == slash { j += 1; continue }
                if isIdentifierStart(c) {
                    let attrStart = j
                    while j < n && isIdentifierChar(buffer[j]) { j += 1 }
                    tokens.append(AtlantisToken(kind: .attrName, range: NSRange(location: attrStart, length: j - attrStart)))
                    var k = j
                    while k < n && isWhitespace(buffer[k]) { k += 1 }
                    if k < n && buffer[k] == equalsSign {
                        k += 1
                        while k < n && isWhitespace(buffer[k]) { k += 1 }
                        if k < n, buffer[k] == quote || buffer[k] == singleQuote {
                            let delim = buffer[k]
                            let valueStart = k
                            k += 1
                            while k < n && buffer[k] != delim { k += 1 }
                            if k < n { k += 1 }
                            tokens.append(AtlantisToken(kind: .attrValue, range: NSRange(location: valueStart, length: k - valueStart)))
                            j = k
                            continue
                        }
                    }
                    continue
                }
                j += 1
            }
            if j < n { j += 1 } // consume '>'
            i = j
        }

        return tokens
    }

    // MARK: - Line starts

    /// Index (in UTF-16 code units) of the start of every line. The empty string
    /// and a string with no trailing newline both report their true line count —
    /// a trailing `\n` never adds a phantom final line.
    static func lineStarts(in buffer: [UInt16]) -> [Int] {
        var starts = [0]
        let n = buffer.count
        var i = 0
        while i < n {
            if buffer[i] == 0x0A {
                let next = i + 1
                if next < n { starts.append(next) }
            }
            i += 1
        }
        return starts
    }

    static func lineStarts(in text: String) -> [Int] {
        lineStarts(in: Array(text.utf16))
    }

    // MARK: - Attributed string builder

    /// Builds the canvas `NSAttributedString` for `text`: base font/color/paragraph
    /// style over the whole string, then each token's color layered on top. The
    /// result's UTF-16 `length` always equals `(text as NSString).length` — no
    /// surrogate pair is ever split, since tokens carry UTF-16 ranges already.
    static func attributedString(text: String,
                                  tokens: [AtlantisToken],
                                  font: AtlantisSyntaxTheme.PlatformFont,
                                  paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        result.addAttribute(.font, value: font, range: fullRange)
        result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.color(for: .plain), range: fullRange)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        for token in tokens {
            guard token.range.location >= 0, NSMaxRange(token.range) <= fullRange.length else { continue }
            result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.color(for: token.kind), range: token.range)
        }
        return result
    }
}

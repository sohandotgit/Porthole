//
//  AtlantisBodyContent.swift
//  atlantis
//

import Foundation

/// Body classification kinds (design §1.1, §3, §5.2). Headless — no SwiftUI import.
enum AtlantisBodyClassifiedKind: Equatable {
    case empty
    case json
    case xml
    case html
    case form
    case text
    case image
    case binary

    /// Uppercase badge string (design §3 row 1).
    var badge: String {
        switch self {
        case .empty: return ""
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .form: return "FORM"
        case .text: return "TEXT"
        case .image: return "IMAGE"
        case .binary: return "BINARY"
        }
    }

    var wrapMode: AtlantisBodyWrapMode {
        switch self {
        case .text: return .word
        default: return .character
        }
    }
}

enum AtlantisBodyWrapMode: Equatable {
    case character
    case word
}

/// Result of classifying a body: kind plus the counts and pretty/raw text the
/// stats line and canvas need. `prettyText`/`rawText` are `nil` when that
/// representation does not apply to the kind (e.g. no `rawText` for `.binary`,
/// no `prettyText` for `.text`).
struct AtlantisBodyClassification {
    let kind: AtlantisBodyClassifiedKind
    let byteCount: Int
    let prettyText: String?
    let rawText: String?
    let prettyLineCount: Int
    let rawLineCount: Int
    /// Computed once by `classify` (B5-5) — never re-scan `Data` on every body
    /// evaluation the way a computed property reading `utf8Diagnosis(data)` would.
    let utf8InvalidByteCount: Int?
    let utf8FirstInvalidOffset: Int?
    /// `.binary`'s lossy UTF-8 decode and its line count, produced once here
    /// rather than on every body evaluation (B-6) — `rawText` stays `nil` for
    /// `.binary` (no valid decode exists), so Raw mode and the gated stats line
    /// read these instead.
    let binaryLossyText: String?
    let binaryLossyLineCount: Int

    var utf8Diagnosis: (invalidByteCount: Int, firstInvalidOffset: Int)? {
        guard let invalidByteCount = utf8InvalidByteCount, let firstInvalidOffset = utf8FirstInvalidOffset else { return nil }
        return (invalidByteCount, firstInvalidOffset)
    }
}

/// Classifies a body's bytes + Content-Type into a kind, with pretty/raw text and
/// line counts, and diagnoses invalid UTF-8. Headless — no SwiftUI import.
enum AtlantisBodyClassifier {

    /// Case-insensitive Content-Type header lookup (today's behavior at
    /// `AtlantisTrafficDetailView.swift:15-17`, lifted here so it's testable headless).
    static func contentType(from headers: [Header]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    static func classify(_ data: Data, contentType: String?) -> AtlantisBodyClassification {
        guard !data.isEmpty else {
            return AtlantisBodyClassification(kind: .empty, byteCount: 0, prettyText: nil, rawText: nil,
                                               prettyLineCount: 0, rawLineCount: 0,
                                               utf8InvalidByteCount: nil, utf8FirstInvalidOffset: nil,
                                               binaryLossyText: nil, binaryLossyLineCount: 0)
        }

        let byteCount = data.count
        let ct = contentType?.lowercased() ?? ""
        // Computed once here (B5-5) — every `AtlantisBodyClassification` this
        // function returns carries it, so nothing downstream re-scans `data`.
        let diagnosis = utf8Diagnosis(data)

        // Image wins over everything, including JSON-looking bytes (design §5.12).
        if ct.hasPrefix("image/") || sniffImage(data) {
            return AtlantisBodyClassification(kind: .image, byteCount: byteCount, prettyText: nil, rawText: nil,
                                               prettyLineCount: 0, rawLineCount: 0,
                                               utf8InvalidByteCount: diagnosis?.invalidByteCount,
                                               utf8FirstInvalidOffset: diagnosis?.firstInvalidOffset,
                                               binaryLossyText: nil, binaryLossyLineCount: 0)
        }

        if let jsonObject = jsonObjectIfValid(data) {
            let pretty = prettyJSON(jsonObject)
            let raw = String(data: data, encoding: .utf8)
            return classification(.json, byteCount: byteCount, pretty: pretty, raw: raw, diagnosis: diagnosis)
        }

        if ct.contains("xml"), let raw = String(data: data, encoding: .utf8) {
            return classification(.xml, byteCount: byteCount, pretty: prettyMarkup(raw), raw: raw, diagnosis: diagnosis)
        }

        if ct.contains("html"), let raw = String(data: data, encoding: .utf8) {
            return classification(.html, byteCount: byteCount, pretty: prettyMarkup(raw), raw: raw, diagnosis: diagnosis)
        }

        if ct.contains("x-www-form-urlencoded"), let raw = String(data: data, encoding: .utf8) {
            return classification(.form, byteCount: byteCount, pretty: prettyForm(raw), raw: raw, diagnosis: diagnosis)
        }

        // Preserves today's behavior at AtlantisTrafficDetailView.swift:47-49: a UTF-8
        // decodable body stays textual even with a binary Content-Type (design §5.2,
        // spec §5.11).
        if let raw = String(data: data, encoding: .utf8) {
            return classification(.text, byteCount: byteCount, pretty: nil, raw: raw, diagnosis: diagnosis)
        }

        let lossyText = String(decoding: data, as: UTF8.self)
        let lossyLineCount = AtlantisSyntaxHighlighter.lineStarts(in: lossyText).count
        return AtlantisBodyClassification(kind: .binary, byteCount: byteCount, prettyText: nil, rawText: nil,
                                           prettyLineCount: 0, rawLineCount: 0,
                                           utf8InvalidByteCount: diagnosis?.invalidByteCount,
                                           utf8FirstInvalidOffset: diagnosis?.firstInvalidOffset,
                                           binaryLossyText: lossyText, binaryLossyLineCount: lossyLineCount)
    }

    /// `(invalidByteCount, firstInvalidOffset)`, `nil` when `data` decodes as clean
    /// UTF-8. Uses `Unicode.UTF8.ForwardParser`, the same maximal-subpart error
    /// recovery Swift's own lossy UTF-8 decoding relies on, so the count/offset match
    /// exactly what `String(decoding:as: UTF8.self)` would replace with U+FFFD.
    static func utf8Diagnosis(_ data: Data) -> (invalidByteCount: Int, firstInvalidOffset: Int)? {
        guard !data.isEmpty else { return nil }

        var iterator = data.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        var offset = 0
        var invalidByteCount = 0
        var firstInvalidOffset: Int?

        loop: while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid(let encoded):
                offset += encoded.count
            case .error(let length):
                if firstInvalidOffset == nil { firstInvalidOffset = offset }
                invalidByteCount += length
                offset += length
            case .emptyInput:
                break loop
            }
        }

        guard let firstOffset = firstInvalidOffset else { return nil }
        return (invalidByteCount, firstOffset)
    }

    // MARK: - Kind probes

    private static func classification(_ kind: AtlantisBodyClassifiedKind, byteCount: Int, pretty: String?, raw: String?,
                                        diagnosis: (invalidByteCount: Int, firstInvalidOffset: Int)?) -> AtlantisBodyClassification {
        AtlantisBodyClassification(
            kind: kind,
            byteCount: byteCount,
            prettyText: pretty,
            rawText: raw,
            prettyLineCount: pretty.map { AtlantisSyntaxHighlighter.lineStarts(in: $0).count } ?? 0,
            rawLineCount: raw.map { AtlantisSyntaxHighlighter.lineStarts(in: $0).count } ?? 0,
            utf8InvalidByteCount: diagnosis?.invalidByteCount,
            utf8FirstInvalidOffset: diagnosis?.firstInvalidOffset,
            binaryLossyText: nil,
            binaryLossyLineCount: 0
        )
    }

    private static func jsonObjectIfValid(_ data: Data) -> Any? {
        guard data.count < 5 * 1024 * 1024 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func prettyJSON(_ object: Any) -> String? {
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    /// Best-effort XML/HTML reindentation — not a validating parser, just enough to
    /// put each tag on its own line so `prettyText` reads as multi-line.
    private static func prettyMarkup(_ raw: String) -> String {
        var result = ""
        var depth = 0
        var i = raw.startIndex
        let end = raw.endIndex

        while i < end {
            if raw[i] == "<" {
                var j = raw.index(after: i)
                while j < end && raw[j] != ">" { j = raw.index(after: j) }
                if j < end { j = raw.index(after: j) }
                let tag = String(raw[i..<j])
                let isClosing = tag.hasPrefix("</")
                let isVoid = tag.hasSuffix("/>") || tag.hasPrefix("<!")

                if isClosing { depth = max(0, depth - 1) }
                if !result.isEmpty { result += "\n" }
                result += String(repeating: "  ", count: depth) + tag
                if !isClosing && !isVoid { depth += 1 }
                i = j
            } else {
                var j = i
                while j < end && raw[j] != "<" { j = raw.index(after: j) }
                let text = String(raw[i..<j]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result += text }
                i = j
            }
        }
        return result
    }

    private static func prettyForm(_ raw: String) -> String {
        raw.split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                let decoded = pair.removingPercentEncoding ?? String(pair)
                return decoded.replacingOccurrences(of: "+", with: " ")
            }
            .joined(separator: "\n")
    }

    private static func sniffImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard !bytes.isEmpty else { return false }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true } // PNG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }                               // JPEG
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return true } // GIF
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return true // WEBP
        }
        if bytes.starts(with: Array("BM".utf8)) { return true } // BMP
        return false
    }

}

/// The UTF-8 failure banner string (design §6.3).
enum AtlantisBodyBanner {
    static func utf8Text(invalidByteCount: Int, firstInvalidOffset: Int) -> String {
        let noun = invalidByteCount == 1 ? "byte" : "bytes"
        let offsetHex = String(format: "%04X", firstInvalidOffset)
        return "Not valid UTF-8 — \(AtlantisBodyStats.grouped(invalidByteCount)) undecodable \(noun) " +
            "at offset 0x\(offsetHex). Showing hex dump instead."
    }
}

/// One line of the per-mode stats-line contract (design §4).
enum AtlantisBodyStatLine {
    case pretty(byteCount: Int, lineCount: Int)
    case gated(byteCount: Int, lineCount: Int)
    /// `.image`'s gated variant — an image has no lines, so this reports bytes
    /// only rather than consulting a line count that doesn't apply (B-6). The
    /// mock does not pin this string.
    case gatedImage(byteCount: Int)
    case hex(byteCount: Int)
    case raw(byteCount: Int, lineCount: Int)
    case text(byteCount: Int, lineCount: Int)
    case image(badge: String, width: Int, height: Int, byteCount: Int)
}

/// Locale-independent number grouping and the exact per-mode stats strings
/// (design §4). Headless — no SwiftUI import.
enum AtlantisBodyStats {

    /// Comma-grouped every three digits, independent of `Locale.current` — never
    /// `NumberFormatter` (tests must be stable in any locale).
    static func grouped(_ n: Int) -> String {
        let sign = n < 0 ? "-" : ""
        let digits = String(abs(n))
        var groups: [Substring] = []
        var remaining = Substring(digits)
        while remaining.count > 3 {
            let cut = remaining.index(remaining.endIndex, offsetBy: -3)
            groups.insert(remaining[cut...], at: 0)
            remaining = remaining[..<cut]
        }
        groups.insert(remaining, at: 0)
        return sign + groups.joined(separator: ",")
    }

    static func statsLine(_ line: AtlantisBodyStatLine) -> String {
        switch line {
        case .pretty(let byteCount, let lineCount):
            return "\(AtlantisFormat.bytes(byteCount)) · \(grouped(lineCount)) lines · pretty-printed"
        case .gated(let byteCount, let lineCount):
            return "\(AtlantisFormat.bytes(byteCount)) · \(grouped(lineCount)) lines · not yet rendered"
        case .gatedImage(let byteCount):
            return "\(AtlantisFormat.bytes(byteCount)) · not yet rendered"
        case .hex(let byteCount):
            let rows = AtlantisHexDump.rowCount(forByteCount: byteCount)
            return "\(AtlantisFormat.bytes(byteCount)) · \(grouped(byteCount)) bytes · \(grouped(rows)) hex rows"
        case .raw(let byteCount, let lineCount):
            return "\(AtlantisFormat.bytes(byteCount)) · \(grouped(lineCount)) lines · raw"
        case .text(let byteCount, let lineCount):
            return "\(AtlantisFormat.bytes(byteCount)) · \(grouped(lineCount)) lines"
        case .image(let badge, let width, let height, let byteCount):
            return "\(badge) · \(width)×\(height) · \(AtlantisFormat.bytes(byteCount))"
        }
    }
}

/// The large-body gate predicate and its user-facing strings (design §6.2).
enum AtlantisBodyGate {
    static func isGated(byteCount: Int, limit: Int, revealed: Bool) -> Bool {
        !revealed && byteCount > limit
    }

    static func footnote(limit: Int) -> String {
        "Auto-render limit: \(AtlantisFormat.bytes(limit)) · change in Settings"
    }

    static func explanation(byteCount: Int, badge: String) -> String {
        "\(AtlantisFormat.bytes(byteCount)) of \(badge). Pretty-printing and highlighting this much " +
            "text may take a moment and can hitch scrolling."
    }
}

/// Which side of the exchange a body belongs to (design §6.6).
enum AtlantisBodySide: Equatable {
    case request
    case response
}

/// Empty-state hint text builder (design §6.5-§6.6). Headless.
enum AtlantisBodyEmptyHint {
    static let byteLine = "0 bytes"

    private static let bodylessMethods: Set<String> = ["GET", "HEAD", "DELETE", "OPTIONS", "TRACE"]

    static func text(method: String, side: AtlantisBodySide, statusCode: Int?) -> String {
        switch side {
        case .request:
            let upper = method.uppercased()
            if bodylessMethods.contains(upper) {
                return "\(upper) requests usually have no body. Nothing was sent on the wire."
            }
            return "The request had no body. Nothing was sent on the wire."
        case .response:
            if statusCode == 204 { return "204 No Content responses never carry a body." }
            if statusCode == 304 { return "304 Not Modified responses never carry a body." }
            return "The response had no body. Nothing was received on the wire."
        }
    }
}

/// Canvas chip cluster contents (design §5.3).
enum AtlantisBodyChip: Equatable {
    case wrap
    case lineNumbers
    case copy
    case asciiPane
    case expandCollapseAll
}

/// Body viewer mode (design §5.2) and its per-kind option matrix.
enum AtlantisBodyMode: Hashable {
    case pretty
    case tree
    case raw
    case hex
    case text
    case image

    var label: String {
        switch self {
        case .pretty: return "Pretty"
        case .tree: return "Tree"
        case .raw: return "Raw"
        case .hex: return "Hex"
        case .text: return "Text"
        case .image: return "Image"
        }
    }

    var showsSearchRow: Bool {
        switch self {
        case .pretty, .tree, .raw, .text: return true
        case .hex, .image: return false
        }
    }

    static func options(for kind: AtlantisBodyClassifiedKind)
        -> (options: [AtlantisBodyMode], defaultMode: AtlantisBodyMode?, disabled: Set<AtlantisBodyMode>, showsPicker: Bool) {
        switch kind {
        case .json:
            return ([.pretty, .tree, .raw, .hex], .pretty, [], true)
        case .xml, .html, .form:
            return ([.pretty, .raw, .hex], .pretty, [], true)
        case .text:
            return ([.text, .hex], .text, [], true)
        case .image:
            return ([.image, .hex], .image, [], true)
        case .binary:
            return ([.pretty, .raw, .hex], .hex, [.pretty], true)
        case .empty:
            return ([], nil, [], false)
        }
    }

    static func chips(for mode: AtlantisBodyMode) -> [AtlantisBodyChip] {
        switch mode {
        case .pretty, .raw, .text: return [.wrap, .lineNumbers, .copy]
        case .tree: return [.expandCollapseAll, .copy]
        case .hex: return [.asciiPane, .copy]
        case .image: return [.copy]
        }
    }
}

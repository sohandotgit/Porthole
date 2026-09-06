//
//  AtlantisJSONValue.swift
//  atlantis
//

import Foundation

/// An order-preserving JSON value tree. Unlike `JSONSerialization`'s `Any`
/// (which loses key order and reformats numbers through `Double`), this keeps
/// object keys in source order and numbers as their original literal text —
/// both of which the tree view needs to render faithfully. Headless — no
/// SwiftUI import.
indirect enum AtlantisJSONValue {
    case object([(key: String, value: AtlantisJSONValue)])
    case array([AtlantisJSONValue])
    case string(String)
    /// Raw numeric literal text, e.g. `"128"` or `"3.14e10"` — never converted
    /// to `Double`, which would lose precision and reformat the literal.
    case number(String)
    case bool(Bool)
    case null
}

/// A minimal, order-preserving recursive-descent JSON parser over raw bytes.
/// `AtlantisBodyClassifier` already validates JSON with `JSONSerialization`
/// before anything reaches this parser, so this one is best-effort: it does
/// not need to produce rich diagnostics, only a faithful tree for input that
/// is already known to be valid JSON. Headless — no SwiftUI import.
enum AtlantisJSONParser {
    static func parse(_ data: Data) -> AtlantisJSONValue? {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        guard let value = parser.parseValue() else { return nil }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skipWhitespace() {
            while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        }

        mutating func parseValue() -> AtlantisJSONValue? {
            skipWhitespace()
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case 0x7B: return parseObject()
            case 0x5B: return parseArray()
            case 0x22: return parseString().map(AtlantisJSONValue.string)
            case 0x74: return parseLiteral("true", .bool(true))
            case 0x66: return parseLiteral("false", .bool(false))
            case 0x6E: return parseLiteral("null", .null)
            default: return parseNumber()
            }
        }

        mutating func parseObject() -> AtlantisJSONValue? {
            i += 1 // {
            var pairs: [(key: String, value: AtlantisJSONValue)] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == 0x7D { i += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                guard i < bytes.count, bytes[i] == 0x22, let key = parseString() else { return nil }
                skipWhitespace()
                guard i < bytes.count, bytes[i] == 0x3A else { return nil } // :
                i += 1
                guard let value = parseValue() else { return nil }
                pairs.append((key, value))
                skipWhitespace()
                guard i < bytes.count else { return nil }
                if bytes[i] == 0x2C { i += 1; continue } // ,
                if bytes[i] == 0x7D { i += 1; break }    // }
                return nil
            }
            return .object(pairs)
        }

        mutating func parseArray() -> AtlantisJSONValue? {
            i += 1 // [
            var items: [AtlantisJSONValue] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == 0x5D { i += 1; return .array(items) }
            while true {
                guard let value = parseValue() else { return nil }
                items.append(value)
                skipWhitespace()
                guard i < bytes.count else { return nil }
                if bytes[i] == 0x2C { i += 1; continue } // ,
                if bytes[i] == 0x5D { i += 1; break }    // ]
                return nil
            }
            return .array(items)
        }

        mutating func parseString() -> String? {
            guard i < bytes.count, bytes[i] == 0x22 else { return nil }
            i += 1
            var out: [UInt8] = []
            while i < bytes.count {
                let b = bytes[i]
                if b == 0x22 { i += 1; return String(decoding: out, as: UTF8.self) }
                if b == 0x5C {
                    i += 1
                    guard i < bytes.count else { return nil }
                    switch bytes[i] {
                    case 0x22: out.append(0x22); i += 1
                    case 0x5C: out.append(0x5C); i += 1
                    case 0x2F: out.append(0x2F); i += 1
                    case 0x62: out.append(0x08); i += 1
                    case 0x66: out.append(0x0C); i += 1
                    case 0x6E: out.append(0x0A); i += 1
                    case 0x72: out.append(0x0D); i += 1
                    case 0x74: out.append(0x09); i += 1
                    case 0x75:
                        i += 1
                        guard let unit = readHex4() else { return nil }
                        var scalarValue = UInt32(unit)
                        if unit >= 0xD800 && unit <= 0xDBFF {
                            guard i + 1 < bytes.count, bytes[i] == 0x5C, bytes[i + 1] == 0x75 else { return nil }
                            i += 2
                            guard let low = readHex4(), low >= 0xDC00, low <= 0xDFFF else { return nil }
                            scalarValue = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
                        }
                        if let scalar = Unicode.Scalar(scalarValue) {
                            out.append(contentsOf: Array(String(scalar).utf8))
                        }
                    default: return nil
                    }
                } else {
                    out.append(b); i += 1
                }
            }
            return nil
        }

        mutating func readHex4() -> UInt16? {
            guard i + 4 <= bytes.count else { return nil }
            var value: UInt16 = 0
            for _ in 0..<4 {
                guard let digit = hexDigit(bytes[i]) else { return nil }
                value = value << 4 | UInt16(digit)
                i += 1
            }
            return value
        }

        func hexDigit(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30
            case 0x41...0x46: return b - 0x41 + 10
            case 0x61...0x66: return b - 0x61 + 10
            default: return nil
            }
        }

        mutating func parseNumber() -> AtlantisJSONValue? {
            let start = i
            if i < bytes.count, bytes[i] == 0x2D { i += 1 } // -
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
            if i < bytes.count, bytes[i] == 0x2E {
                i += 1
                while i < bytes.count, isDigit(bytes[i]) { i += 1 }
            }
            if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
                var j = i + 1
                if j < bytes.count, bytes[j] == 0x2B || bytes[j] == 0x2D { j += 1 }
                if j < bytes.count, isDigit(bytes[j]) {
                    i = j
                    while i < bytes.count, isDigit(bytes[i]) { i += 1 }
                }
            }
            guard i > start else { return nil }
            return .number(String(decoding: bytes[start..<i], as: UTF8.self))
        }

        mutating func parseLiteral(_ literal: String, _ value: AtlantisJSONValue) -> AtlantisJSONValue? {
            let chars = Array(literal.utf8)
            guard i + chars.count <= bytes.count else { return nil }
            for k in 0..<chars.count where bytes[i + k] != chars[k] { return nil }
            i += chars.count
            return value
        }

        func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
        func isWhitespace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }
    }
}

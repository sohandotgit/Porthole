//
//  AtlantisHexDump.swift
//  atlantis
//

import Foundation

/// Canonical hex dump builder (design §6.4): 16 bytes/row, uppercase, double gap
/// after byte 8, fixed-width byte field so the ASCII pane always starts at the same
/// column even on a short final row. Headless — no SwiftUI import.
struct AtlantisHexDump {
    let text: String
    let tokens: [AtlantisToken]
    let truncatedFrom: Int?
    let rowCount: Int

    static let byteLimit = 1_048_576

    /// Row count for a *full* byte count, capped at `byteLimit` — used by the stats
    /// line so it never has to materialize a multi-megabyte dump just to count rows.
    static func rowCount(forByteCount byteCount: Int) -> Int {
        let capped = min(byteCount, byteLimit)
        guard capped > 0 else { return 0 }
        return (capped + 15) / 16
    }

    static func build(_ data: Data, asciiVisible: Bool = true) -> AtlantisHexDump {
        let bytes = [UInt8](data)
        let total = bytes.count
        let dumpCount = min(total, byteLimit)
        let truncatedFrom = total > byteLimit ? total : nil

        var out = ""
        out.reserveCapacity((dumpCount / 16 + 1) * 78)
        var tokens: [AtlantisToken] = []

        // Every character appended below is ASCII, so the UTF-16 length grows by
        // exactly the character count — track it directly instead of re-bridging
        // the accumulated string to NSString on every row (was O(n²)).
        var utf16Offset = 0

        var offset = 0
        while offset < dumpCount {
            let rowByteCount = min(16, dumpCount - offset)

            let offsetStart = utf16Offset
            let offsetString = hexOffset(offset)
            out += offsetString
            utf16Offset += offsetString.count
            tokens.append(AtlantisToken(kind: .hexOffset, range: NSRange(location: offsetStart, length: 8)))
            out += "  "
            utf16Offset += 2

            let byteFieldStart = utf16Offset
            for i in 0..<16 {
                if i < rowByteCount {
                    out += hexByte(bytes[offset + i])
                } else {
                    out += "  "
                }
                utf16Offset += 2
                if i < 15 {
                    let gap = (i == 7) ? "  " : " "
                    out += gap
                    utf16Offset += gap.count
                }
            }
            tokens.append(AtlantisToken(kind: .hexBytes, range: NSRange(location: byteFieldStart, length: 48)))

            if asciiVisible {
                out += "  "
                utf16Offset += 2
                let asciiStart = utf16Offset
                for i in 0..<rowByteCount {
                    out.append(asciiChar(bytes[offset + i]))
                }
                utf16Offset += rowByteCount
                if rowByteCount > 0 {
                    tokens.append(AtlantisToken(kind: .hexAscii, range: NSRange(location: asciiStart, length: rowByteCount)))
                }
            }
            out += "\n"
            utf16Offset += 1
            offset += 16
        }

        if let truncatedFrom = truncatedFrom {
            out += "Showing first 1 MB of \(AtlantisFormat.bytes(truncatedFrom))"
        }

        return AtlantisHexDump(text: out, tokens: tokens, truncatedFrom: truncatedFrom,
                                rowCount: dumpCount == 0 ? 0 : (dumpCount + 15) / 16)
    }

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    private static func hexByte(_ b: UInt8) -> String {
        String([hexDigits[Int(b >> 4)], hexDigits[Int(b & 0x0F)]])
    }

    private static func hexOffset(_ value: Int) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    private static func asciiChar(_ b: UInt8) -> Character {
        (b >= 0x20 && b <= 0x7E) ? Character(UnicodeScalar(b)) : "."
    }
}

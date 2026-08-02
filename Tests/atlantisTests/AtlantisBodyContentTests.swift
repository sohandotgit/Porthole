//
//  AtlantisBodyContentTests.swift
//  atlantis
//
//  Tests/body-viewer.spec.md §4-6 — AtlantisHexDump, AtlantisBodyClassifier,
//  AtlantisBodyClassifier.utf8Diagnosis.
//

import Foundation
import XCTest
@testable import Atlantis

// MARK: - 4. AtlantisHexDump

final class AtlantisHexDumpTests: XCTestCase {

    func test4_1_singleShortRowExactString() {
        let dump = AtlantisHexDump.build(Data([0x41, 0x42]))
        let expected = "00000000  41 42                                             AB\n"
        XCTAssertEqual(dump.text, expected)
        XCTAssertEqual(dump.text.filter { $0 == "\n" }.count, 1)
    }

    func test4_2_fullRowExactString() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
        let dump = AtlantisHexDump.build(data)
        let expected = "00000000  89 50 4E 47 0D 0A 1A 0A  00 00 00 0D 49 48 44 52  .PNG........IHDR\n"
        XCTAssertEqual(dump.text, expected)
    }

    func test4_3_doubleGapPosition() {
        let data = Data(0..<16)
        let dump = AtlantisHexDump.build(data)
        let row = dump.text as NSString
        let byteField = row.substring(with: NSRange(location: 10, length: 48))
        // exactly one two-space run, starting at index 23 of the field
        var doubleSpaceRanges: [Int] = []
        var searchStart = byteField.startIndex
        while let range = byteField.range(of: "  ", range: searchStart..<byteField.endIndex) {
            doubleSpaceRanges.append(byteField.distance(from: byteField.startIndex, to: range.lowerBound))
            searchStart = range.upperBound
        }
        XCTAssertEqual(doubleSpaceRanges, [23])
    }

    func test4_4_alignment() {
        let full = AtlantisHexDump.build(Data(0..<16))
        let short = AtlantisHexDump.build(Data(0..<3))
        let fullAsciiToken = full.tokens.first { $0.kind == .hexAscii }
        let shortAsciiToken = short.tokens.first { $0.kind == .hexAscii }
        XCTAssertEqual(fullAsciiToken?.range.location, 60)
        XCTAssertEqual(shortAsciiToken?.range.location, 60)
    }

    func test4_5_offsetsAdvance() {
        let dump = AtlantisHexDump.build(Data(repeating: 0, count: 33))
        let offsetTokens = dump.tokens.filter { $0.kind == .hexOffset }
        let nsText = dump.text as NSString
        let offsets = offsetTokens.map { nsText.substring(with: $0.range) }
        XCTAssertEqual(offsets, ["00000000", "00000010", "00000020"])
    }

    func test4_6_offsetIsUppercaseHex() {
        let dump = AtlantisHexDump.build(Data(repeating: 0xFF, count: 0xB0 + 1))
        let nsText = dump.text as NSString
        let offsets = dump.tokens.filter { $0.kind == .hexOffset }.map { nsText.substring(with: $0.range) }
        XCTAssertTrue(offsets.contains("000000A0"))
    }

    func test4_7_nonPrintablesBecomeDotsSpaceStaysSpace() {
        let dump = AtlantisHexDump.build(Data([0x00, 0x7F, 0x20, 0x7E]))
        let nsText = dump.text as NSString
        guard let asciiToken = dump.tokens.first(where: { $0.kind == .hexAscii }) else {
            return XCTFail("no ascii token")
        }
        XCTAssertEqual(nsText.substring(with: asciiToken.range), ".. ~")
    }

    func test4_8_truncation() {
        let count = AtlantisHexDump.byteLimit + 10
        let dump = AtlantisHexDump.build(Data(repeating: 0xFF, count: count))
        XCTAssertEqual(dump.truncatedFrom, count)
        XCTAssertEqual(dump.rowCount, AtlantisHexDump.byteLimit / 16)
        XCTAssertEqual(dump.rowCount, 65_536)
        let lines = dump.text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.last, "Showing first 1 MB of 1.0 MB")
    }

    func test4_9_footerWordingForBiggerBody() {
        let dump = AtlantisHexDump.build(Data(repeating: 0xFF, count: 2_621_440))
        let lines = dump.text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.last, "Showing first 1 MB of 2.5 MB")
    }

    func test4_10_noTruncationUnderCap() {
        let dump = AtlantisHexDump.build(Data(repeating: 0x41, count: 1024))
        XCTAssertNil(dump.truncatedFrom)
        XCTAssertFalse(dump.text.contains("Showing first"))
    }

    func test4_11_rowCount() {
        XCTAssertEqual(AtlantisHexDump.build(Data(repeating: 0, count: 6_248)).rowCount, 391)
        XCTAssertEqual(AtlantisHexDump.build(Data(repeating: 0, count: 16)).rowCount, 1)
        XCTAssertEqual(AtlantisHexDump.build(Data(repeating: 0, count: 17)).rowCount, 2)
        XCTAssertEqual(AtlantisHexDump.build(Data()).rowCount, 0)
    }

    func test4_12_tokensAreInBoundsAndTyped() {
        let dump = AtlantisHexDump.build(Data(0..<40))
        let length = (dump.text as NSString).length
        for token in dump.tokens {
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), length)
        }
        let offsetTokens = dump.tokens.filter { $0.kind == .hexOffset }
        XCTAssertTrue(offsetTokens.allSatisfy { $0.range.length == 8 })
        XCTAssertEqual(offsetTokens.count, dump.rowCount)
        XCTAssertEqual(dump.tokens.filter { $0.kind == .hexBytes }.count, dump.rowCount)
        XCTAssertEqual(dump.tokens.filter { $0.kind == .hexAscii }.count, dump.rowCount)
    }

    func test4_13_asciiPaneOff() {
        let dump = AtlantisHexDump.build(Data(0..<16), asciiVisible: false)
        XCTAssertEqual(dump.tokens.filter { $0.kind == .hexAscii }.count, 0)
        let rows = dump.text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        for row in rows {
            XCTAssertEqual(row.count, 58)
        }
    }

    func test4_14_emptyData() {
        let dump = AtlantisHexDump.build(Data())
        XCTAssertEqual(dump.text, "")
        XCTAssertNil(dump.truncatedFrom)
        XCTAssertEqual(dump.tokens, [])
        XCTAssertEqual(dump.rowCount, 0)
    }
}

// MARK: - 5. AtlantisBodyClassifier — kind, counts, pretty-printing

final class AtlantisBodyClassifierTests: XCTestCase {

    func test5_1_empty() {
        let result = AtlantisBodyClassifier.classify(Data(), contentType: nil)
        XCTAssertEqual(result.kind, .empty)
        XCTAssertEqual(result.byteCount, 0)
        XCTAssertNil(result.prettyText)
        XCTAssertNil(result.rawText)
    }

    func test5_2_json() {
        let data = Data(#"{"b":1,"a":2}"#.utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/json")
        XCTAssertEqual(result.kind, .json)
        guard let pretty = result.prettyText else { return XCTFail("no prettyText") }
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertLessThan(pretty.range(of: "\"a\"")!.lowerBound, pretty.range(of: "\"b\"")!.lowerBound)
        XCTAssertEqual(AtlantisSyntaxHighlighter.lineStarts(in: pretty).count, 4)
    }

    func test5_3_jsonDetectedWithoutContentType() {
        let data = Data(#"{"b":1,"a":2}"#.utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: nil)
        XCTAssertEqual(result.kind, .json)
    }

    func test5_4_xml() {
        let data = Data("<root><a/></root>".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/xml")
        XCTAssertEqual(result.kind, .xml)
        XCTAssertNotNil(result.prettyText)
        XCTAssertTrue(result.prettyText!.contains("\n"))
    }

    func test5_5_html() {
        let data = Data("<html><body>hi</body></html>".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "text/html")
        XCTAssertEqual(result.kind, .html)
    }

    func test5_6_formURLEncoded() {
        let data = Data("a=1&b=hello%20world".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/x-www-form-urlencoded")
        XCTAssertEqual(result.kind, .form)
        guard let pretty = result.prettyText else { return XCTFail("no prettyText") }
        XCTAssertEqual(pretty.split(separator: "\n").count, 2)
        XCTAssertTrue(pretty.contains("hello world"))
    }

    func test5_7_plainText() {
        let data = Data("hello".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "text/plain")
        XCTAssertEqual(result.kind, .text)
        XCTAssertEqual(result.rawText, "hello")
        XCTAssertNil(result.prettyText)
    }

    private let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    func test5_8_imageByContentType() {
        let result = AtlantisBodyClassifier.classify(onePixelPNG, contentType: "image/png")
        XCTAssertEqual(result.kind, .image)
    }

    func test5_9_imageBySniffing() {
        let result = AtlantisBodyClassifier.classify(onePixelPNG, contentType: nil)
        XCTAssertEqual(result.kind, .image)
    }

    func test5_10_binary() {
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/octet-stream")
        XCTAssertEqual(result.kind, .binary)
        XCTAssertNil(result.rawText)
    }

    func test5_11_utf8BodyWithBinaryContentTypeStillDecodes() {
        let data = Data("hi".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/octet-stream")
        XCTAssertEqual(result.kind, .text)
    }

    /// B5-5: `classify` computes the UTF-8 diagnosis once and hands it back on
    /// the classification, rather than a caller re-scanning `data` itself.
    func test5_16_classificationCarriesUTF8Diagnosis() {
        let invalidData = Data([0xFF, 0xFE, 0x00, 0x01])
        let invalidResult = AtlantisBodyClassifier.classify(invalidData, contentType: "application/octet-stream")
        let diag = invalidResult.utf8Diagnosis
        XCTAssertNotNil(diag)
        XCTAssertEqual(diag?.firstInvalidOffset, 0)

        let validResult = AtlantisBodyClassifier.classify(Data("hi".utf8), contentType: nil)
        XCTAssertNil(validResult.utf8Diagnosis)
    }

    func test5_12_imageContentTypeWinsOverJSONLookingBytes() {
        let result = AtlantisBodyClassifier.classify(onePixelPNG, contentType: "image/png")
        XCTAssertNotEqual(result.kind, .json)
    }

    func test5_13_contentTypeIsCaseInsensitive() {
        let headers = [Header(key: "content-TYPE", value: "application/json")]
        XCTAssertEqual(AtlantisBodyClassifier.contentType(from: headers), "application/json")
    }

    func test5_14_formatTraits() {
        XCTAssertEqual(AtlantisBodyClassifiedKind.json.wrapMode, .character)
        XCTAssertEqual(AtlantisBodyClassifiedKind.text.wrapMode, .word)
        XCTAssertEqual(AtlantisBodyClassifiedKind.json.badge, "JSON")
        XCTAssertEqual(AtlantisBodyClassifiedKind.binary.badge, "BINARY")
        XCTAssertEqual(AtlantisBodyClassifiedKind.form.badge, "FORM")
    }

    func test5_15_rawLineCountIsANewlineScanNotAProjection() {
        let pairs = (0..<200).map { "\"k\($0)\":\($0)" }.joined(separator: ",")
        let data = Data("{\(pairs)}".utf8)
        let result = AtlantisBodyClassifier.classify(data, contentType: "application/json")
        XCTAssertEqual(result.kind, .json)
        XCTAssertEqual(result.rawLineCount, 1)
        XCTAssertGreaterThan(result.prettyLineCount, 1)
    }
}

// MARK: - 6. AtlantisBodyClassifier.utf8Diagnosis

final class AtlantisUTF8DiagnosisTests: XCTestCase {

    func test6_1_cleanASCII() {
        XCTAssertNil(AtlantisBodyClassifier.utf8Diagnosis(Data("hello".utf8)))
    }

    func test6_2_cleanMultiByte() {
        XCTAssertNil(AtlantisBodyClassifier.utf8Diagnosis(Data("héllo🙂".utf8)))
    }

    func test6_3_empty() {
        XCTAssertNil(AtlantisBodyClassifier.utf8Diagnosis(Data()))
    }

    func test6_4_theMocksCase() {
        let data = Data([0x41, 0x42, 0x43, 0x44, 0xFF, 0xFE, 0xFD, 0xFC, 0x45])
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(data)
        XCTAssertEqual(diagnosis?.invalidByteCount, 4)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 4)
    }

    func test6_5_firstByteInvalid() {
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(Data([0xFF, 0x41]))
        XCTAssertEqual(diagnosis?.invalidByteCount, 1)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 0)
    }

    func test6_6_truncatedMultiByteSequenceAtEnd() {
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(Data([0x41, 0xE2, 0x82]))
        XCTAssertEqual(diagnosis?.invalidByteCount, 2)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 1)
    }

    func test6_7_loneContinuationByte() {
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(Data([0x41, 0x80, 0x42]))
        XCTAssertEqual(diagnosis?.invalidByteCount, 1)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 1)
    }

    func test6_8_surrogateEncodingIsInvalid() {
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(Data([0xED, 0xA0, 0x80]))
        XCTAssertEqual(diagnosis?.invalidByteCount, 3)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 0)
    }

    func test6_9_countIsOfInvalidBytesNotSequences() {
        let diagnosis = AtlantisBodyClassifier.utf8Diagnosis(Data([0xFF, 0x41, 0xFF, 0xFF]))
        XCTAssertEqual(diagnosis?.invalidByteCount, 3)
        XCTAssertEqual(diagnosis?.firstInvalidOffset, 0)
    }

    func test6_10_bannerString() {
        XCTAssertEqual(AtlantisBodyBanner.utf8Text(invalidByteCount: 4, firstInvalidOffset: 4),
                        "Not valid UTF-8 — 4 undecodable bytes at offset 0x0004. Showing hex dump instead.")
    }

    func test6_11_bannerSingular() {
        XCTAssertEqual(AtlantisBodyBanner.utf8Text(invalidByteCount: 1, firstInvalidOffset: 0),
                        "Not valid UTF-8 — 1 undecodable byte at offset 0x0000. Showing hex dump instead.")
    }

    func test6_12_bannerOffsetPaddingAndCase() {
        XCTAssertTrue(AtlantisBodyBanner.utf8Text(invalidByteCount: 2, firstInvalidOffset: 65_536)
            .contains("at offset 0x10000"))
        XCTAssertTrue(AtlantisBodyBanner.utf8Text(invalidByteCount: 2, firstInvalidOffset: 2748)
            .contains("at offset 0x0ABC"))
    }

    func test6_13_bannerGrouping() {
        XCTAssertTrue(AtlantisBodyBanner.utf8Text(invalidByteCount: 1234, firstInvalidOffset: 0)
            .contains("1,234 undecodable bytes"))
    }
}

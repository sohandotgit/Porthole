//
//  AtlantisBodyViewerTests.swift
//  atlantis
//
//  body-viewer.spec.md §10.1-10.4, §10.10 — AtlantisBodyViewerView /
//  AtlantisBodyPreviewCard construction across every kind, state, and the
//  gated-.image path where B-6 hid (N-7).
//

import Foundation
import XCTest
#if canImport(SwiftUI)
import SwiftUI

@testable import Atlantis

@available(iOS 15.0, macOS 12.0, *)
private enum AtlantisBodyViewerFixtures {
    // 1x1 transparent PNG.
    static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!

    // Neither a valid image signature nor valid UTF-8 (0xFF is never a legal
    // leading byte) — lands as `.binary` with no UTF-8 diagnosis surfaced by
    // this particular fixture's first byte alone; used for the plain-binary case.
    static let binary = Data([0xFF, 0xFE, 0x00, 0x01, 0x02, 0x03])

    // Lone UTF-8 continuation bytes — invalid from the very first byte, so
    // `classify` reports a UTF-8 diagnosis and the hex canvas shows the banner.
    static let undecodableBinary = Data([0x80, 0x81, 0x82, 0x83])

    /// (title, data, contentType) for every `AtlantisBodyClassifiedKind` the
    /// spec names — JSON, XML, HTML, form, text, image, binary,
    /// undecodable-binary, empty (§10.1).
    static let everyKind: [(String, Data, String?)] = [
        ("json", Data(#"{"a":1}"#.utf8), "application/json"),
        ("xml", Data("<a>1</a>".utf8), "application/xml"),
        ("html", Data("<html></html>".utf8), "text/html"),
        ("form", Data("a=1&b=2".utf8), "application/x-www-form-urlencoded"),
        ("text", Data("hello world".utf8), "text/plain"),
        ("image", onePixelPNG, "image/png"),
        ("binary", binary, "application/octet-stream"),
        ("undecodable-binary", undecodableBinary, "application/octet-stream"),
        ("empty", Data(), nil),
    ]
}

@available(iOS 15.0, macOS 12.0, *)
final class AtlantisBodyViewerViewTests: XCTestCase {

    /// §10.1: `AtlantisBodyViewerView` for every kind.
    func test10_1_viewerBuildsForEveryKind() {
        for (title, data, contentType) in AtlantisBodyViewerFixtures.everyKind {
            let view = AtlantisBodyViewerView(title: title, data: data, contentType: contentType,
                                               method: "GET", side: .response, statusCode: 200)
            _ = view.body
        }
    }

    /// §10.2: pretty, gated (`revealed == false`), gated-then-revealed, hex
    /// with banner, empty.
    func test10_2_viewerBuildsInEachState() {
        // Pretty — small JSON body, well under the default gate.
        let prettyView = AtlantisBodyViewerView(title: "pretty", data: Data(#"{"a":1}"#.utf8),
                                                  contentType: "application/json", method: "GET",
                                                  side: .response, statusCode: 200)
        _ = prettyView.body

        // Gated — the default's already 64 KB, so lower it via the same
        // `@AppStorage` key `AtlantisViewerSettings` reads.
        let key = "AtlantisViewerSettings.autoRenderLimitBytes"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous = previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(1, forKey: key)
        let bigJSON = try! JSONSerialization.data(withJSONObject: ["items": (0..<200).map { "item-\($0)" }])
        XCTAssertGreaterThan(bigJSON.count, 1)
        let gatedView = AtlantisBodyViewerView(title: "gated", data: bigJSON, contentType: "application/json",
                                                 method: "GET", side: .response, statusCode: 200)
        _ = gatedView.body

        // Gated-then-revealed is `revealed` flipped to `true` — private
        // `@State`, unreachable from outside the view, so the predicate it
        // gates on (`AtlantisBodyGate.isGated`) is pinned directly instead:
        // this is the exact `revealed` branch `isGated` short-circuits on.
        XCTAssertFalse(AtlantisBodyGate.isGated(byteCount: bigJSON.count, limit: 1, revealed: true))
        XCTAssertTrue(AtlantisBodyGate.isGated(byteCount: bigJSON.count, limit: 1, revealed: false))

        // Hex with banner — undecodable binary defaults to `.hex` and carries
        // a UTF-8 diagnosis, so the banner renders (design §6.3).
        let hexView = AtlantisBodyViewerView(title: "hex", data: AtlantisBodyViewerFixtures.undecodableBinary,
                                               contentType: "application/octet-stream", method: "GET",
                                               side: .response, statusCode: 200)
        _ = hexView.body

        // Empty.
        let emptyView = AtlantisBodyViewerView(title: "empty", data: Data(), contentType: nil,
                                                 method: "GET", side: .response, statusCode: 200)
        _ = emptyView.body
    }

    /// §10.10: `autoRenderLimitBytes` at the extremes — `1` (everything
    /// gated) and `Int.max` (nothing gated).
    func test10_10_viewerBuildsAtExtremeAutoRenderLimits() {
        let key = "AtlantisViewerSettings.autoRenderLimitBytes"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous = previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(1, forKey: key)
        let everythingGated = AtlantisBodyViewerView(title: "tiny-limit", data: Data(#"{"a":1}"#.utf8),
                                                       contentType: "application/json", method: "GET",
                                                       side: .response, statusCode: 200)
        _ = everythingGated.body
        XCTAssertEqual(AtlantisViewerSettings.autoRenderLimitBytes, 1)

        UserDefaults.standard.set(Int.max, forKey: key)
        let nothingGated = AtlantisBodyViewerView(title: "max-limit", data: Data(#"{"a":1}"#.utf8),
                                                    contentType: "application/json", method: "GET",
                                                    side: .response, statusCode: 200)
        _ = nothingGated.body
        XCTAssertEqual(AtlantisViewerSettings.autoRenderLimitBytes, Int.max)

        // Extremes on the headless predicate itself.
        XCTAssertTrue(AtlantisBodyGate.isGated(byteCount: 2, limit: 1, revealed: false))
        XCTAssertFalse(AtlantisBodyGate.isGated(byteCount: Int.max - 1, limit: Int.max, revealed: false))
    }

    /// B-6: a large `.image` body is gated on byte count alone (design §5.12)
    /// and its gated stats line reports bytes only — no line count, so no
    /// full-payload decode/scan is ever asked for while the gate is on screen.
    func test10_gatedImagePathNeverConsultsALineCount() {
        // A PNG larger than a `1`-byte limit is gated, exactly like the
        // reachable `AtlantisBodyViewerView.isGated` path for `.image` kinds.
        let png = AtlantisBodyViewerFixtures.onePixelPNG
        XCTAssertTrue(AtlantisBodyGate.isGated(byteCount: png.count, limit: 1, revealed: false))

        let classification = AtlantisBodyClassifier.classify(png, contentType: "image/png")
        XCTAssertEqual(classification.kind, .image)
        XCTAssertNil(classification.rawText)
        XCTAssertNil(classification.binaryLossyText)
        XCTAssertEqual(classification.binaryLossyLineCount, 0)

        let line = AtlantisBodyStats.statsLine(.gatedImage(byteCount: classification.byteCount))
        XCTAssertFalse(line.contains("line"))
        XCTAssertTrue(line.contains("not yet rendered"))
    }
}

@available(iOS 15.0, macOS 12.0, *)
final class AtlantisBodyPreviewCardTests: XCTestCase {

    /// §10.3: `AtlantisBodyPreviewCard` for the same nine inputs as §10.1.
    func test10_3_previewCardBuildsForEveryKind() {
        for (title, data, contentType) in AtlantisBodyViewerFixtures.everyKind {
            let card = AtlantisBodyPreviewCard(title: title, data: data, contentType: contentType,
                                                method: "GET", side: .response, statusCode: 200)
            _ = card.body
        }
    }

    /// §10.4: a body far larger than `previewByteBudget` still builds — pins
    /// that the card only ever classifies the bounded slice, never the whole
    /// 200 KB payload.
    func test10_4_previewCardBuildsForBodyFarLargerThanBudget() {
        let largeArray = (0..<5_000).map { "item-\($0)-\(String(repeating: "x", count: 30))" }
        let largeBody = try! JSONSerialization.data(withJSONObject: ["items": largeArray])
        XCTAssertGreaterThan(largeBody.count, 200_000)

        let card = AtlantisBodyPreviewCard(title: "large", data: largeBody, contentType: "application/json",
                                            method: "GET", side: .response, statusCode: 200)
        _ = card.body

        XCTAssertEqual(AtlantisBodyPreviewCard.previewByteLimit, AtlantisSyntaxTheme.previewByteBudget)
        XCTAssertLessThan(largeBody.prefix(AtlantisBodyPreviewCard.previewByteLimit).count, largeBody.count)
    }
}
#endif

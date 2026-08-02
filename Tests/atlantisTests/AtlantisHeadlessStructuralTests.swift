//
//  AtlantisHeadlessStructuralTests.swift
//  atlantis
//

import Foundation
import XCTest
@testable import Atlantis

/// Spec §11 — structural CI assertions over the source tree itself, not just
/// runtime behavior. These exist so a regression like B3-1 (a "headless" file
/// that still imports SwiftUI) fails a test instead of only a manual review.
final class AtlantisHeadlessStructuralTests: XCTestCase {

    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AtlantisHeadlessStructuralTests.swift
            .deletingLastPathComponent() // atlantisTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources")
    }

    private func contents(of fileName: String) throws -> String {
        try String(contentsOf: sourcesDirectory.appendingPathComponent(fileName), encoding: .utf8)
    }

    func test11_1_headlessFilesNeverImportSwiftUI() throws {
        for fileName in ["AtlantisSyntaxHighlighter.swift", "AtlantisHexDump.swift",
                          "AtlantisBodyContent.swift", "AtlantisFormat.swift"] {
            let text = try contents(of: fileName)
            let hasImportLine = text.split(separator: "\n").contains { line in
                line.trimmingCharacters(in: .whitespaces) == "import SwiftUI"
            }
            XCTAssertFalse(hasImportLine, "\(fileName) must not import SwiftUI")
        }
    }

    func test11_2_noRawColorLiteralsOutsideSyntaxTheme() throws {
        let forbidden = ["Color(red:", ".yellow", ".orange", ".blue"]
        let files = ["AtlantisBodyViewerView.swift", "AtlantisBodyContent.swift",
                     "AtlantisBodyPreviewCard.swift", "AtlantisHexDump.swift",
                     "AtlantisCodeTextView.swift"]
        for fileName in files {
            let text = try contents(of: fileName)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(fileName) contains forbidden color literal \(token)")
            }
        }
    }

    func test11_3_removedSymbolsStayRemoved() throws {
        let forbidden = ["AtlantisBodySectionView", "atlantisJSONTokens",
                          "AtlantisSelectableText", "atlantisLargeBodyThreshold"]
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) still references \(token)")
            }
        }
    }

    func test11_4_publicAPIDidNotGrow() throws {
        // Scoped to the viewer path (design §1.5) — the wider library
        // (network capture, `TrafficPackage`, etc.) has its own legitimate
        // public API this assertion isn't about.
        let viewerPathFiles = ["AtlantisBodyViewerView.swift", "AtlantisBodyContent.swift",
                                "AtlantisBodyPreviewCard.swift", "AtlantisCodeTextView.swift",
                                "AtlantisSyntaxTheme.swift", "AtlantisSyntaxHighlighter.swift",
                                "AtlantisBodySearch.swift", "AtlantisHexDump.swift", "AtlantisFormat.swift",
                                "AtlantisTrafficListView.swift", "AtlantisTrafficDetailView.swift"]
        let allowedPublicTypes: Set<String> = ["AtlantisTrafficListView", "AtlantisTrafficDetailView", "AtlantisBodySearch"]
        let pattern = try NSRegularExpression(pattern: #"public\s+(struct|class|enum)\s+(\w+)"#)
        var foundTypes: Set<String> = []
        for fileName in viewerPathFiles {
            let text = try contents(of: fileName)
            let range = NSRange(text.startIndex..., in: text)
            pattern.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match = match, let nameRange = Range(match.range(at: 2), in: text) else { return }
                foundTypes.insert(String(text[nameRange]))
            }
        }
        XCTAssertEqual(foundTypes, allowedPublicTypes)
    }

    func test10_8_colorForKindIsExhaustive() {
        let kinds: [AtlantisTokenKind] = [.key, .string, .number, .literal, .punctuation, .plain,
                                           .tagName, .attrName, .attrValue, .comment,
                                           .hexOffset, .hexBytes, .hexAscii]
        for kind in kinds {
            _ = AtlantisSyntaxTheme.color(for: kind) // must not trap; presence is the assertion
        }
    }
}

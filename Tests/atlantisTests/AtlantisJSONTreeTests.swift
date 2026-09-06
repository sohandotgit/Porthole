//
//  AtlantisJSONTreeTests.swift
//  atlantis
//
//  Tests for the JSON tree view's headless model: AtlantisJSONParser
//  (order-preserving JSON parsing) and AtlantisJSONTree (row flattening,
//  default expansion, search).
//

import Foundation
import XCTest
@testable import Atlantis

// MARK: - AtlantisJSONParser

final class AtlantisJSONParserTests: XCTestCase {

    func testPreservesKeyOrderUnlikeJSONSerializationSorted() {
        let json = #"{"zeta": 1, "alpha": 2, "mid": 3}"#
        guard case .object(let pairs)? = AtlantisJSONParser.parse(Data(json.utf8)) else {
            return XCTFail("expected object")
        }
        XCTAssertEqual(pairs.map(\.key), ["zeta", "alpha", "mid"])
    }

    func testPreservesNumberLiteralText() {
        let json = #"{"a": 1.50, "b": 3.14e10, "c": -7}"#
        guard case .object(let pairs)? = AtlantisJSONParser.parse(Data(json.utf8)) else {
            return XCTFail("expected object")
        }
        let values = Dictionary(uniqueKeysWithValues: pairs)
        guard case .number(let a)? = values["a"], case .number(let b)? = values["b"], case .number(let c)? = values["c"] else {
            return XCTFail("expected numbers")
        }
        XCTAssertEqual(a, "1.50")
        XCTAssertEqual(b, "3.14e10")
        XCTAssertEqual(c, "-7")
    }

    func testStringEscapesAndUnicodeEscape() {
        let json = #"{"s": "line\nbreak \"quoted\" é"}"#
        guard case .object(let pairs)? = AtlantisJSONParser.parse(Data(json.utf8)),
              case .string(let s)? = pairs.first?.value else {
            return XCTFail("expected string")
        }
        XCTAssertEqual(s, "line\nbreak \"quoted\" é")
    }

    func testSurrogatePairEscape() {
        let json = #"{"emoji": "😀"}"#
        guard case .object(let pairs)? = AtlantisJSONParser.parse(Data(json.utf8)),
              case .string(let s)? = pairs.first?.value else {
            return XCTFail("expected string")
        }
        XCTAssertEqual(s, "😀")
    }

    func testNestedArraysAndObjects() {
        let json = #"{"items": [1, {"nested": true}, null]}"#
        guard case .object(let pairs)? = AtlantisJSONParser.parse(Data(json.utf8)),
              case .array(let items)? = pairs.first?.value else {
            return XCTFail("expected array")
        }
        XCTAssertEqual(items.count, 3)
        guard case .number("1") = items[0] else { return XCTFail("expected number") }
        guard case .object(let inner) = items[1], case .bool(true) = inner.first!.value else { return XCTFail("expected nested bool") }
        guard case .null = items[2] else { return XCTFail("expected null") }
    }

    func testEmptyObjectAndArray() {
        XCTAssertEqual(AtlantisJSONParser.parse(Data(#"{}"#.utf8)).map { if case .object(let p) = $0 { return p.count } else { return -1 } }, 0)
        XCTAssertEqual(AtlantisJSONParser.parse(Data(#"[]"#.utf8)).map { if case .array(let a) = $0 { return a.count } else { return -1 } }, 0)
    }

    func testMalformedInputReturnsNil() {
        XCTAssertNil(AtlantisJSONParser.parse(Data(#"{"a": }"#.utf8)))
        XCTAssertNil(AtlantisJSONParser.parse(Data(#"not json"#.utf8)))
    }
}

// MARK: - AtlantisJSONTree

final class AtlantisJSONTreeTests: XCTestCase {

    private func sampleRoot() -> AtlantisJSONValue {
        .object([
            ("requestId", .string("9f3a-77b1-4c02")),
            ("user", .object([
                ("id", .number("4821")),
                ("verified", .bool(true))
            ])),
            ("roles", .array([.string("admin"), .string("editor")])),
            ("count", .number("128"))
        ])
    }

    func testRootLevelRowsHaveDepthZero() {
        let root = sampleRoot()
        let expanded = AtlantisJSONTree.defaultExpandedPaths(root: root)
        let rows = AtlantisJSONTree.rows(root: root, expanded: expanded)
        let rootLabels = rows.filter { $0.depth == 0 }.map(\.keyLabel)
        XCTAssertEqual(rootLabels, ["requestId", "user", "roles", "count"])
    }

    func testCollapsedContainerShowsCountPreview() {
        let root = sampleRoot()
        let rows = AtlantisJSONTree.rows(root: root, expanded: [])
        let user = rows.first { $0.keyLabel == "user" }
        XCTAssertEqual(user?.valuePreview, "{ 2 }")
        let roles = rows.first { $0.keyLabel == "roles" }
        XCTAssertEqual(roles?.valuePreview, "[ 2 ]")
    }

    func testExpandedContainerHasNoInlinePreviewAndListsChildren() {
        let root = sampleRoot()
        let userPath: AtlantisJSONPath = [.key("user")]
        let rows = AtlantisJSONTree.rows(root: root, expanded: [userPath])
        let user = rows.first { $0.path == userPath }
        XCTAssertEqual(user?.valuePreview, "")
        XCTAssertTrue(rows.contains { $0.keyLabel == "id" && $0.depth == 1 })
        XCTAssertTrue(rows.contains { $0.keyLabel == "verified" && $0.depth == 1 })
    }

    func testStringValuesAreQuoted() {
        let root = sampleRoot()
        let rows = AtlantisJSONTree.rows(root: root, expanded: [])
        let requestId = rows.first { $0.keyLabel == "requestId" }
        XCTAssertEqual(requestId?.valuePreview, "\"9f3a-77b1-4c02\"")
    }

    func testDefaultExpandedPathsExpandsRootLevelSmallContainers() {
        let root = sampleRoot()
        let expanded = AtlantisJSONTree.defaultExpandedPaths(root: root)
        XCTAssertTrue(expanded.contains([.key("user")]))
        XCTAssertTrue(expanded.contains([.key("roles")]))
    }

    func testDefaultExpandedPathsCollapsesLargeNestedContainer() {
        let manyItems = (0..<50).map { AtlantisJSONValue.number("\($0)") }
        let root = AtlantisJSONValue.object([("big", .object([("items", .array(manyItems))]))])
        let expanded = AtlantisJSONTree.defaultExpandedPaths(root: root)
        // "big" is root-level, so it's always expanded regardless of size.
        XCTAssertTrue(expanded.contains([.key("big")]))
        // "items" is nested (depth 1) with 50 children, over the auto-expand limit.
        XCTAssertFalse(expanded.contains([.key("big"), .key("items")]))
    }

    func testAllExpandablePathsIncludesEveryContainer() {
        let root = sampleRoot()
        let all = AtlantisJSONTree.allExpandablePaths(root: root)
        XCTAssertEqual(all, [[.key("user")], [.key("roles")]])
    }

    func testMatchingPathsFindsKeyAndValueMatches() {
        let root = sampleRoot()
        let byKey = AtlantisJSONTree.matchingPaths(root: root, query: "requestId")
        XCTAssertEqual(byKey, [[.key("requestId")]])

        let byValue = AtlantisJSONTree.matchingPaths(root: root, query: "admin")
        XCTAssertEqual(byValue, [[.key("roles"), .index(0)]])
    }

    func testMatchingPathsIsCaseInsensitiveAndEmptyQueryReturnsNoMatches() {
        let root = sampleRoot()
        XCTAssertEqual(AtlantisJSONTree.matchingPaths(root: root, query: "ADMIN"), [[.key("roles"), .index(0)]])
        XCTAssertEqual(AtlantisJSONTree.matchingPaths(root: root, query: ""), [])
        XCTAssertEqual(AtlantisJSONTree.matchingPaths(root: root, query: "   "), [])
    }

    func testAncestorsOfPathReturnsProperPrefixes() {
        let path: AtlantisJSONPath = [.key("roles"), .index(0)]
        XCTAssertEqual(AtlantisJSONTree.ancestors(of: path), [[.key("roles")]])
        XCTAssertEqual(AtlantisJSONTree.ancestors(of: [.key("count")]), [])
        XCTAssertEqual(AtlantisJSONTree.ancestors(of: []), [])
    }

    func testTopLevelArrayRoot() {
        let root = AtlantisJSONValue.array([.number("1"), .number("2")])
        let rows = AtlantisJSONTree.rows(root: root, expanded: [])
        XCTAssertEqual(rows.map(\.keyLabel), ["0", "1"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }
}

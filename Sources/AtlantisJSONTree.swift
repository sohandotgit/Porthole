//
//  AtlantisJSONTree.swift
//  atlantis
//

import Foundation

/// One step into a JSON value: an object key or an array index. A sequence of
/// these uniquely identifies a node in an `AtlantisJSONValue` tree — used as
/// the expanded-set key and row identity, since JSON object keys are not
/// guaranteed unique across siblings at different depths but a full path is.
enum AtlantisJSONPathComponent: Hashable {
    case key(String)
    case index(Int)
}

typealias AtlantisJSONPath = [AtlantisJSONPathComponent]

enum AtlantisJSONTreeValueKind: Equatable {
    case object
    case array
    case string
    case number
    case bool
    case null
}

/// One flattened, visible row of the tree (design: "Tree row"). Produced by
/// `AtlantisJSONTree.rows(root:expanded:)` from the current expanded-path set
/// — collapsing a node simply omits its descendants from this list, so the
/// view never needs to reason about visibility itself.
struct AtlantisJSONTreeRow: Identifiable, Equatable {
    let path: AtlantisJSONPath
    let depth: Int
    /// Object key, or the stringified index for an array element.
    let keyLabel: String
    let isExpandable: Bool
    let isExpanded: Bool
    /// `{ 4 }` / `[ 2 ]` for a collapsed container; empty for an expanded
    /// container (children render as subsequent rows); the formatted leaf
    /// value otherwise (design: "Value / preview").
    let valuePreview: String
    let valueKind: AtlantisJSONTreeValueKind

    var id: AtlantisJSONPath { path }
}

/// Headless flattening/search logic for the JSON tree view — no SwiftUI
/// import, so it's usable from a background task and independently testable.
enum AtlantisJSONTree {

    /// Containers with more children than this default to collapsed the first
    /// time they're seen, so an unexpectedly huge array/object doesn't flood
    /// the initial row list (design: "Default: root-level nodes expanded
    /// except large/collapsed-by-default ones").
    static let defaultAutoExpandChildLimit = 8

    /// Longest a leaf preview string gets before truncation (design: "Leaf
    /// values are colored by type" — truncation keeps a single huge string
    /// from making its row unreadable or the canvas unscrollable-feeling).
    static let maxLeafPreviewLength = 200

    // MARK: - Flattening

    static func rows(root: AtlantisJSONValue, expanded: Set<AtlantisJSONPath>) -> [AtlantisJSONTreeRow] {
        var rows: [AtlantisJSONTreeRow] = []
        forEachChild(of: root) { child, path, keyLabel in
            flatten(child, path: path, depth: 0, keyLabel: keyLabel, expanded: expanded, into: &rows)
        }
        return rows
    }

    private static func flatten(_ value: AtlantisJSONValue, path: AtlantisJSONPath, depth: Int, keyLabel: String,
                                 expanded: Set<AtlantisJSONPath>, into rows: inout [AtlantisJSONTreeRow]) {
        switch value {
        case .object(let pairs):
            let isExpanded = expanded.contains(path)
            rows.append(AtlantisJSONTreeRow(path: path, depth: depth, keyLabel: keyLabel, isExpandable: true,
                                             isExpanded: isExpanded, valuePreview: isExpanded ? "" : "{ \(pairs.count) }",
                                             valueKind: .object))
            guard isExpanded else { return }
            for (key, child) in pairs {
                flatten(child, path: path + [.key(key)], depth: depth + 1, keyLabel: key, expanded: expanded, into: &rows)
            }
        case .array(let items):
            let isExpanded = expanded.contains(path)
            rows.append(AtlantisJSONTreeRow(path: path, depth: depth, keyLabel: keyLabel, isExpandable: true,
                                             isExpanded: isExpanded, valuePreview: isExpanded ? "" : "[ \(items.count) ]",
                                             valueKind: .array))
            guard isExpanded else { return }
            for (index, child) in items.enumerated() {
                flatten(child, path: path + [.index(index)], depth: depth + 1, keyLabel: "\(index)", expanded: expanded, into: &rows)
            }
        case .string(let s):
            rows.append(leafRow(path: path, depth: depth, keyLabel: keyLabel, preview: quoted(s), kind: .string))
        case .number(let raw):
            rows.append(leafRow(path: path, depth: depth, keyLabel: keyLabel, preview: truncate(raw), kind: .number))
        case .bool(let b):
            rows.append(leafRow(path: path, depth: depth, keyLabel: keyLabel, preview: b ? "true" : "false", kind: .bool))
        case .null:
            rows.append(leafRow(path: path, depth: depth, keyLabel: keyLabel, preview: "null", kind: .null))
        }
    }

    private static func leafRow(path: AtlantisJSONPath, depth: Int, keyLabel: String, preview: String,
                                 kind: AtlantisJSONTreeValueKind) -> AtlantisJSONTreeRow {
        AtlantisJSONTreeRow(path: path, depth: depth, keyLabel: keyLabel, isExpandable: false, isExpanded: false,
                             valuePreview: preview, valueKind: kind)
    }

    private static func quoted(_ s: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(s.count + 2)
        for c in s {
            switch c {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default: escaped.append(c)
            }
        }
        return "\"\(truncate(escaped))\""
    }

    private static func truncate(_ s: String) -> String {
        guard s.count > maxLeafPreviewLength else { return s }
        return String(s.prefix(maxLeafPreviewLength)) + "…"
    }

    // MARK: - Default expansion

    /// Root-level containers are expanded by default; a container at any
    /// depth whose child count exceeds `defaultAutoExpandChildLimit` stays
    /// collapsed so its own (large) subtree isn't auto-expanded either.
    static func defaultExpandedPaths(root: AtlantisJSONValue) -> Set<AtlantisJSONPath> {
        var expanded: Set<AtlantisJSONPath> = []
        forEachChild(of: root) { child, path, _ in
            visit(child, path: path, depth: 0, into: &expanded)
        }
        return expanded
    }

    private static func visit(_ value: AtlantisJSONValue, path: AtlantisJSONPath, depth: Int, into expanded: inout Set<AtlantisJSONPath>) {
        switch value {
        case .object(let pairs):
            guard depth == 0 || pairs.count <= defaultAutoExpandChildLimit else { return }
            expanded.insert(path)
            for (key, child) in pairs { visit(child, path: path + [.key(key)], depth: depth + 1, into: &expanded) }
        case .array(let items):
            guard depth == 0 || items.count <= defaultAutoExpandChildLimit else { return }
            expanded.insert(path)
            for (index, child) in items.enumerated() { visit(child, path: path + [.index(index)], depth: depth + 1, into: &expanded) }
        default:
            break
        }
    }

    // MARK: - Expand/collapse all

    /// Every expandable node's path, for the toolbar's "expand all".
    static func allExpandablePaths(root: AtlantisJSONValue) -> Set<AtlantisJSONPath> {
        var all: Set<AtlantisJSONPath> = []
        forEachChild(of: root) { child, path, _ in
            visitAll(child, path: path, into: &all)
        }
        return all
    }

    private static func visitAll(_ value: AtlantisJSONValue, path: AtlantisJSONPath, into all: inout Set<AtlantisJSONPath>) {
        switch value {
        case .object(let pairs):
            all.insert(path)
            for (key, child) in pairs { visitAll(child, path: path + [.key(key)], into: &all) }
        case .array(let items):
            all.insert(path)
            for (index, child) in items.enumerated() { visitAll(child, path: path + [.index(index)], into: &all) }
        default:
            break
        }
    }

    // MARK: - Search

    /// Paths of every node whose key label or leaf value contains `query`
    /// (case-insensitive). Order matches document order, matching the
    /// existing text-canvas search's match ordering.
    static func matchingPaths(root: AtlantisJSONValue, query: String) -> [AtlantisJSONPath] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()
        var matches: [AtlantisJSONPath] = []
        forEachChild(of: root) { child, path, keyLabel in
            search(child, path: path, keyLabel: keyLabel, query: q, into: &matches)
        }
        return matches
    }

    private static func search(_ value: AtlantisJSONValue, path: AtlantisJSONPath, keyLabel: String, query: String,
                                into matches: inout [AtlantisJSONPath]) {
        let keyMatches = keyLabel.lowercased().contains(query)
        let valueMatches: Bool
        switch value {
        case .string(let s): valueMatches = s.lowercased().contains(query)
        case .number(let n): valueMatches = n.lowercased().contains(query)
        case .bool(let b): valueMatches = (b ? "true" : "false").contains(query)
        case .null: valueMatches = "null".contains(query)
        case .object, .array: valueMatches = false
        }
        if keyMatches || valueMatches { matches.append(path) }

        switch value {
        case .object(let pairs):
            for (key, child) in pairs { search(child, path: path + [.key(key)], keyLabel: key, query: query, into: &matches) }
        case .array(let items):
            for (index, child) in items.enumerated() {
                search(child, path: path + [.index(index)], keyLabel: "\(index)", query: query, into: &matches)
            }
        default:
            break
        }
    }

    /// Every proper ancestor path of `path` — used to force-expand a match's
    /// containing nodes so the row is actually visible in the flattened list.
    static func ancestors(of path: AtlantisJSONPath) -> [AtlantisJSONPath] {
        guard path.count > 1 else { return [] }
        return (1..<path.count).map { Array(path[0..<$0]) }
    }

    // MARK: - Root traversal

    /// Root-level `(value, path, keyLabel)` triples — an object's top-level
    /// keys, an array's top-level indices, or, for a bodiless-of-container
    /// top-level scalar, a single empty-path/empty-label entry.
    private static func forEachChild(of root: AtlantisJSONValue, _ body: (AtlantisJSONValue, AtlantisJSONPath, String) -> Void) {
        switch root {
        case .object(let pairs):
            for (key, child) in pairs { body(child, [.key(key)], key) }
        case .array(let items):
            for (index, child) in items.enumerated() { body(child, [.index(index)], "\(index)") }
        default:
            body(root, [], "")
        }
    }
}

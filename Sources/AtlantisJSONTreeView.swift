//
//  AtlantisJSONTreeView.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI

/// Renders a flattened `AtlantisJSONTreeRow` list as a collapsible node tree
/// (design_handoff_tree_view: "Tree row"). Row flattening/search stay headless
/// in `AtlantisJSONTree`/`AtlantisJSONValue` — this view only lays the rows
/// out and wires taps back to the expanded-path set it's given.
struct AtlantisJSONTreeView: View {
    let rows: [AtlantisJSONTreeRow]
    let matchedPaths: Set<AtlantisJSONPath>
    let currentMatchPath: AtlantisJSONPath?
    /// Bumped by the owner to trigger a scroll-to-current-match, mirroring
    /// `AtlantisBodyViewerView`'s `scrollToken` convention for the text canvas.
    let scrollToken: Int
    let onToggle: (AtlantisJSONPath) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        AtlantisJSONTreeRowView(row: row,
                                                 isMatch: matchedPaths.contains(row.path),
                                                 isCurrentMatch: currentMatchPath == row.path,
                                                 onToggle: { onToggle(row.path) })
                            .id(row.path)
                    }
                }
                .padding(.vertical, AtlantisSyntaxTheme.treeCanvasPaddingVertical)
                .padding(.horizontal, AtlantisSyntaxTheme.treeCanvasPaddingHorizontal)
            }
            .onChange(of: scrollToken) { _ in
                guard let path = currentMatchPath else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(path, anchor: .center)
                }
            }
        }
    }
}

private struct AtlantisJSONTreeRowView: View {
    let row: AtlantisJSONTreeRow
    let isMatch: Bool
    let isCurrentMatch: Bool
    let onToggle: () -> Void

    private var indent: CGFloat {
        CGFloat(row.depth) * AtlantisSyntaxTheme.treeIndentStep + AtlantisSyntaxTheme.treeIndentBase
    }

    private var valueColor: AtlantisSyntaxTheme.PlatformColor {
        switch row.valueKind {
        case .object, .array: return AtlantisSyntaxTheme.treeCollapsedPreview
        case .string: return AtlantisSyntaxTheme.syntaxString
        case .number: return AtlantisSyntaxTheme.syntaxNumber
        case .bool: return AtlantisSyntaxTheme.syntaxLiteral
        case .null: return AtlantisSyntaxTheme.syntaxLiteral
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<row.depth, id: \.self) { level in
                Rectangle()
                    .fill(Color(AtlantisSyntaxTheme.treeGuideLine))
                    .frame(width: AtlantisSyntaxTheme.treeGuideWidth)
                    .offset(x: CGFloat(level) * AtlantisSyntaxTheme.treeIndentStep + AtlantisSyntaxTheme.treeGuideOffset)
                    .frame(maxHeight: .infinity)
            }

            HStack(alignment: .firstTextBaseline, spacing: AtlantisSyntaxTheme.treeRowGap) {
                Group {
                    if row.isExpandable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: AtlantisSyntaxTheme.treeChevronGlyphSize, weight: .semibold))
                            .foregroundColor(Color(AtlantisSyntaxTheme.syntaxPunctuation))
                            .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: AtlantisSyntaxTheme.treeChevronHitSize, height: AtlantisSyntaxTheme.treeChevronHitSize)

                Text(row.keyLabel)
                    .font(Font(AtlantisSyntaxTheme.treeKeyFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.syntaxKey))

                Text(":")
                    .font(Font(AtlantisSyntaxTheme.treeValueFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.syntaxPunctuation))

                if !row.valuePreview.isEmpty {
                    Text(row.valuePreview)
                        .font(Font(AtlantisSyntaxTheme.treeValueFont))
                        .foregroundColor(Color(valueColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
        }
        .padding(.vertical, AtlantisSyntaxTheme.treeRowPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.treeRowPaddingHorizontal)
        .frame(minHeight: AtlantisSyntaxTheme.treeRowLineHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrentMatch ? Color(AtlantisSyntaxTheme.currentMatchBackground) :
                (isMatch ? Color(AtlantisSyntaxTheme.matchBackground) : Color.clear)
        )
        .cornerRadius(AtlantisSyntaxTheme.matchCornerRadius)
        .contentShape(Rectangle())
        .onTapGesture {
            guard row.isExpandable else { return }
            onToggle()
        }
    }
}
#endif

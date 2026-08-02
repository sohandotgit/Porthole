//
//  AtlantisBodyPreviewCard.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Inline preview card on the detail screen (design §7): header line + trailing
/// byte count + format badge + `›`, then a clipped, non-scrolling,
/// non-selectable canvas of at most the first 14 lines / 2 KB, highlighted, with
/// a bottom fade when clipped. Tapping anywhere pushes `AtlantisBodyViewerView`.
/// Classification and tokenization run on the 2 KB slice only — never the whole
/// payload — so `List` cell cost stays bounded.
struct AtlantisBodyPreviewCard: View {
    static let previewByteLimit = AtlantisSyntaxTheme.previewByteBudget
    static let previewLineLimit = AtlantisSyntaxTheme.previewMaxLines

    let title: String
    let data: Data
    let contentType: String?
    let method: String
    let side: AtlantisBodySide
    let statusCode: Int?

    @State private var built: NSAttributedString?
    @State private var lineStarts: [Int] = [0]
    @State private var wasClipped = false
    @State private var previewKind: AtlantisBodyClassifiedKind = .empty

    private var slice: Data { data.prefix(Self.previewByteLimit) }

    /// Cheap identity for the `.task(id:)` change signal — byte count plus a
    /// prefix hash, so SwiftUI never hashes/compares the full body `Data` on
    /// every cell update (B6-4).
    private struct DataIdentity: Equatable {
        let byteCount: Int
        let prefixHash: Int

        init(_ data: Data) {
            byteCount = data.count
            var hasher = Hasher()
            hasher.combine(data.prefix(256))
            prefixHash = hasher.finalize()
        }
    }

    private var dataIdentity: DataIdentity { DataIdentity(data) }

    var body: some View {
        NavigationLink {
            AtlantisBodyViewerView(title: title, data: data, contentType: contentType,
                                    method: method, side: side, statusCode: statusCode)
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .task(id: dataIdentity) {
            await rebuild()
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.metaCardRowGap) {
            headerRow
            canvas
        }
        .padding(.vertical, AtlantisSyntaxTheme.metaCardPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.metaCardPaddingHorizontal)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
    }

    private var headerRow: some View {
        HStack(spacing: AtlantisSyntaxTheme.metaBadgeGap) {
            Text(title)
                .font(Font(AtlantisSyntaxTheme.contentTypeFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
            Spacer()
            Text(AtlantisFormat.bytes(data.count))
                .font(Font(AtlantisSyntaxTheme.statsFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            if !previewKind.badge.isEmpty {
                Text(previewKind.badge)
                    .font(Font(AtlantisSyntaxTheme.badgeFont))
                    .tracking(0.6)
                    .foregroundColor(Color(badgeColors.fg))
                    .padding(.vertical, AtlantisSyntaxTheme.badgePaddingVertical)
                    .padding(.horizontal, AtlantisSyntaxTheme.badgePaddingHorizontal)
                    .background(Color(badgeColors.fill))
                    .cornerRadius(AtlantisSyntaxTheme.badgeCornerRadius)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: AtlantisSyntaxTheme.previewChevronGlyphSize, weight: .semibold))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelQuaternary))
        }
    }

    private var badgeColors: (fg: AtlantisSyntaxTheme.PlatformColor, fill: AtlantisSyntaxTheme.PlatformColor) {
        switch previewKind {
        case .json: return (AtlantisSyntaxTheme.badgeJSONForeground, AtlantisSyntaxTheme.badgeJSONFill)
        case .xml: return (AtlantisSyntaxTheme.badgeXMLForeground, AtlantisSyntaxTheme.badgeXMLFill)
        case .html: return (AtlantisSyntaxTheme.badgeHTMLForeground, AtlantisSyntaxTheme.badgeHTMLFill)
        case .form: return (AtlantisSyntaxTheme.badgeFormForeground, AtlantisSyntaxTheme.badgeFormFill)
        case .text: return (AtlantisSyntaxTheme.badgeTextForeground, AtlantisSyntaxTheme.badgeTextFill)
        case .image: return (AtlantisSyntaxTheme.badgeImageForeground, AtlantisSyntaxTheme.badgeImageFill)
        case .binary: return (AtlantisSyntaxTheme.badgeBinaryForeground, AtlantisSyntaxTheme.badgeBinaryFill)
        case .empty: return (AtlantisSyntaxTheme.badgeTextForeground, AtlantisSyntaxTheme.badgeTextFill)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        switch previewKind {
        case .empty:
            Text("No body")
                .font(Font(AtlantisSyntaxTheme.contentTypeFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
        case .image:
            thumbnail
        case .binary:
            Text(hexPreviewLine)
                .font(Font(AtlantisSyntaxTheme.hexByteFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.hexBytes))
                .lineLimit(1)
        default:
            // Highlighted, non-scrolling, non-selectable, gutter on (design §7).
            HStack(alignment: .top, spacing: 0) {
                AtlantisStaticGutterText(lineCount: lineStarts.count)
                    .frame(width: gutterWidth)
                ZStack(alignment: .bottom) {
                    // Non-scrolling, non-selectable (design §7, B6-1) — a plain
                    // `draw(in:)` render, never `AtlantisCodeTextView`'s
                    // TextKit/`UITextView` stack, which would pay per-cell layout-
                    // manager cost inside a `List` for a fixed, tiny preview.
                    AtlantisStaticAttributedText(attributed: built ?? NSAttributedString(string: ""))
                        .frame(height: CGFloat(Self.previewLineLimit) * AtlantisSyntaxTheme.canvasLineHeight)
                    if wasClipped {
                        LinearGradient(colors: [Color(AtlantisSyntaxTheme.cardFill).opacity(0), Color(AtlantisSyntaxTheme.cardFill)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: AtlantisSyntaxTheme.previewFadeHeight)
                    }
                }
            }
        }
    }

    /// Gutter column width: `digits × digitWidth + gutterWidthPadding`, floor
    /// `gutterWidthFloor` (design §6.1/§7, tokens.md §8) — same formula the
    /// canvas gutter uses, recomputed here since that one is private to
    /// `AtlantisCodeTextView.swift`.
    private var gutterWidth: CGFloat {
        let digitCount = String(max(lineStarts.count, 1)).count
        let digitWidth = (String(repeating: "0", count: digitCount) as NSString)
            .size(withAttributes: [.font: AtlantisSyntaxTheme.gutterFont]).width
        return max(AtlantisSyntaxTheme.gutterWidthFloor, ceil(CGFloat(digitCount) * digitWidth) + AtlantisSyntaxTheme.gutterWidthPadding)
    }

    // Falls back to the full `data` whenever the 2 KB slice doesn't decode —
    // most image formats need more than a 2 KB prefix to resolve. This is a
    // deliberate exemption from §7's "never decode the whole payload" for
    // image bodies specifically (B6-5); every other kind stays slice-only.
    private var thumbnail: some View {
        Group {
            #if os(iOS) || targetEnvironment(macCatalyst)
            if let uiImage = UIImage(data: slice.count < data.count ? data : slice) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: slice.count < data.count ? data : slice) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fill)
            }
            #endif
        }
        .frame(width: AtlantisSyntaxTheme.previewThumbnailSize, height: AtlantisSyntaxTheme.previewThumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.chipCornerRadius))
    }

    private var hexPreviewLine: String {
        AtlantisHexDump.build(data.prefix(16)).text
            .split(separator: "\n").first.map(String.init) ?? ""
    }

    private struct RebuildResult {
        let kind: AtlantisBodyClassifiedKind
        let attributed: NSAttributedString?
        let lineStarts: [Int]
        let wasClipped: Bool
    }

    /// Classification (JSON parsing, pretty-printing, UTF-8 diagnosis) plus
    /// tokenization all run inside the detached task — the 2 KB slice bound
    /// keeps the cost small, but it is still main-thread work inside a `List`
    /// cell until it's moved off (N-2). `previewKind` and `built` are only
    /// ever written together below, so the canvas never renders a kind whose
    /// `built` hasn't landed yet.
    @MainActor
    private func rebuild() async {
        let sliceData = slice
        let fullByteCount = data.count
        let byteLimit = Self.previewByteLimit
        let lineLimit = Self.previewLineLimit
        let contentType = self.contentType

        let result: RebuildResult = await Task.detached(priority: .userInitiated) {
            let classification = AtlantisBodyClassifier.classify(sliceData, contentType: contentType)
            guard classification.kind != .empty, classification.kind != .image, classification.kind != .binary else {
                return RebuildResult(kind: classification.kind, attributed: nil, lineStarts: [0],
                                      wasClipped: fullByteCount > byteLimit)
            }
            let text = classification.prettyText ?? classification.rawText ?? ""
            var allLineStarts = AtlantisSyntaxHighlighter.lineStarts(in: text)
            var previewText = text
            var clippedByLines = false
            if allLineStarts.count > lineLimit {
                clippedByLines = true
                let cutStart = allLineStarts[lineLimit]
                let nsText = text as NSString
                previewText = nsText.substring(to: min(cutStart, nsText.length))
                allLineStarts = Array(allLineStarts.prefix(lineLimit))
            }
            let tokens: [AtlantisToken]
            switch classification.kind {
            case .json: tokens = AtlantisSyntaxHighlighter.jsonTokens(in: Array(previewText.utf16))
            case .xml, .html: tokens = AtlantisSyntaxHighlighter.xmlTokens(in: Array(previewText.utf16))
            default: tokens = []
            }
            let paragraph = AtlantisSyntaxTheme.paragraphStyle(wrapping: false, wordWrap: false)
            let attributed = AtlantisSyntaxHighlighter.attributedString(text: previewText, tokens: tokens,
                                                                         font: AtlantisSyntaxTheme.canvasFont,
                                                                         paragraphStyle: paragraph)
            let clippedByBytes = fullByteCount > byteLimit
            return RebuildResult(kind: classification.kind, attributed: attributed, lineStarts: allLineStarts,
                                  wasClipped: clippedByBytes || clippedByLines)
        }.value
        guard !Task.isCancelled else { return }
        previewKind = result.kind
        built = result.attributed
        lineStarts = result.lineStarts
        wasClipped = result.wasClipped
    }
}

/// Static line-number column for the preview card (design §7 "gutter on") — a
/// fixed, non-scrolling stack of `Text` numbers rather than the canvas
/// gutter's `CATiledLayer`-style redraw, since the preview is capped at
/// `previewMaxLines` rows (N-1).
private struct AtlantisStaticGutterText: View {
    let lineCount: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<max(lineCount, 1), id: \.self) { index in
                Text("\(index + 1)")
                    .font(Font(AtlantisSyntaxTheme.gutterFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.gutterText))
                    .frame(height: AtlantisSyntaxTheme.canvasLineHeight, alignment: .trailing)
            }
        }
        .padding(.leading, AtlantisSyntaxTheme.gutterPaddingLeading)
        .padding(.trailing, AtlantisSyntaxTheme.gutterPaddingTrailing)
        .background(Color(AtlantisSyntaxTheme.gutterFill))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(AtlantisSyntaxTheme.gutterDivider))
                .frame(width: AtlantisSyntaxTheme.gutterDividerWidth)
        }
    }
}

/// Static, non-scrolling, non-selectable render of a pre-built
/// `NSAttributedString` (design §7, B6-1) — a plain `draw(in:)`, never
/// `AtlantisCodeTextView`'s `UITextView`/TextKit stack, whose per-cell layout
/// manager cost is exactly what a `List` of preview cards must avoid. Fixed,
/// small height only — never the document-height concern `draw(_:)` raises for
/// the full canvas (B4-2).
private struct AtlantisStaticAttributedText: View {
    let attributed: NSAttributedString

    var body: some View {
        _Representable(attributed: attributed)
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
private struct _Representable: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> AtlantisStaticTextRenderView {
        let view = AtlantisStaticTextRenderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AtlantisStaticTextRenderView, context: Context) {
        view.attributed = attributed
    }
}

private final class AtlantisStaticTextRenderView: UIView {
    var attributed: NSAttributedString? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        attributed?.draw(with: bounds, options: [.usesLineFragmentOrigin], context: nil)
    }
}
#elseif os(macOS)
private struct _Representable: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> AtlantisStaticTextRenderView {
        let view = AtlantisStaticTextRenderView()
        return view
    }

    func updateNSView(_ view: AtlantisStaticTextRenderView, context: Context) {
        view.attributed = attributed
    }
}

private final class AtlantisStaticTextRenderView: NSView {
    var attributed: NSAttributedString? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        attributed?.draw(with: bounds, options: [.usesLineFragmentOrigin])
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
#endif

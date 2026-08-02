//
//  AtlantisCodeTextView.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

/// TextKit-1-backed code canvas: a line-number gutter and the pinned current-match
/// ring overlay (design/body-viewer-ui-v2.md §8), search highlight applied by
/// mutating `.backgroundColor` over match ranges only (§9). Owns its own scroll —
/// a parent `List` must never take it over (perf contract rule 3).
///
/// `attributed` is the once-built, fully token-colored string (perf contract rule
/// 2) — this view never rebuilds `textStorage` after the first assignment; it only
/// mutates attributes over `matchRanges`/`currentMatchRange`, clearing exactly the
/// ranges it previously set. `lineStarts` is the same table the gutter and the
/// stats line share (design §4/§6.1).
struct AtlantisCodeTextView: View {
    /// The incrementally-grown render output (Part 1). `version` is the
    /// change signal SwiftUI diffs on; the view appends only the chunks
    /// between its last-applied version and this one (Part 2) — never a full
    /// `textStorage` replace after the stream's first chunk lands.
    let stream: AtlantisBodyStream
    let version: Int
    var matchRanges: [NSRange] = []
    var currentMatchRange: NSRange? = nil
    /// `true` = wrapping (line-break style already baked into `attributed`'s
    /// paragraph style); `false` = no wrap, horizontal scroll, container width
    /// `.greatestFiniteMagnitude` (design §6.1).
    var wrapEnabled: Bool = true
    /// Whether the line-number gutter is drawn (design §5.3 chip) — B5-6.
    var showsLineNumbers: Bool = true
    /// Bump to re-scroll to `currentMatchRange`, one third from the top of the
    /// viewport (design §6.1) — the token, not the range, is the change signal.
    var scrollToken: Int = 0

    var body: some View {
        _Representable(stream: stream, version: version, matchRanges: matchRanges,
                        currentMatchRange: currentMatchRange, wrapEnabled: wrapEnabled,
                        showsLineNumbers: showsLineNumbers, scrollToken: scrollToken)
    }
}

// MARK: - Shared line-number math (binary search over `lineStarts`)

/// Index (into `lineStarts`) of the line containing UTF-16 `location` — the
/// greatest `i` with `lineStarts[i] <= location`. O(log lineStarts.count), never a
/// linear scan (perf contract rule 4).
private func atlantisLineIndex(for location: Int, in lineStarts: [Int]) -> Int {
    guard !lineStarts.isEmpty else { return 0 }
    var lo = 0
    var hi = lineStarts.count - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if lineStarts[mid] <= location { lo = mid } else { hi = mid - 1 }
    }
    return lo
}

/// Gutter column width: `digits × digitWidth + gutterWidthPadding`, floor
/// `gutterWidthFloor` (design §6.1, tokens.md §8). Recompute only when the digit
/// count changes.
private func atlantisGutterWidth(digitCount: Int, digitWidth: CGFloat) -> CGFloat {
    max(AtlantisSyntaxTheme.gutterWidthFloor, ceil(CGFloat(digitCount) * digitWidth) + AtlantisSyntaxTheme.gutterWidthPadding)
}

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit

private struct _Representable: UIViewRepresentable {
    let stream: AtlantisBodyStream
    let version: Int
    var matchRanges: [NSRange]
    var currentMatchRange: NSRange?
    var wrapEnabled: Bool
    var showsLineNumbers: Bool
    var scrollToken: Int

    func makeUIView(context: Context) -> UIView {
        let coordinator = context.coordinator
        let container = AtlantisCodeContainerView()
        container.layoutHandler = { [weak coordinator] in coordinator?.relayout() }

        // TextKit 1 pinned — the gutter and ring overlay both use
        // NSLayoutManager fragment geometry (perf contract rule 6).
        let textView = UITextView(usingTextLayoutManager: false)
        let inset = AtlantisSyntaxTheme.canvasInset
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: AtlantisSyntaxTheme.canvasOverscrollBottom, right: 0)
        textView.textContainer.lineFragmentPadding = AtlantisSyntaxTheme.lineFragmentPadding
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = coordinator

        let gutter = AtlantisGutterView()
        gutter.isUserInteractionEnabled = false

        let overlay = AtlantisMatchOverlayView(frame: .zero)
        overlay.isUserInteractionEnabled = false
        textView.addSubview(overlay)

        container.addSubview(gutter)
        container.addSubview(textView)

        coordinator.textView = textView
        coordinator.gutterView = gutter
        coordinator.overlayView = overlay
        coordinator.container = container

        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }

        if coordinator.appliedStream !== stream {
            coordinator.appliedStream = stream
            coordinator.appliedVersion = 0
            coordinator.baseAttributed = NSMutableAttributedString()
            coordinator.lineStarts = []
            textView.textStorage.setAttributedString(NSAttributedString())
            coordinator.appliedMatchRanges = []
            coordinator.appliedCurrentRange = nil
        }

        // Version-delta append (Part 2) — only the chunks not yet applied are
        // appended to `textStorage`; never a full replace after the first
        // chunk lands (O(n) total across a stream, not O(n²)).
        if version > coordinator.appliedVersion {
            let storage = textView.textStorage
            let base = coordinator.baseAttributed ?? NSMutableAttributedString()
            storage.beginEditing()
            for i in coordinator.appliedVersion..<version where i < stream.chunks.count {
                let chunk = stream.chunks[i]
                storage.append(chunk.attributed)
                base.append(chunk.attributed)
                coordinator.lineStarts.append(contentsOf: chunk.lineStarts)
            }
            storage.endEditing()
            coordinator.baseAttributed = base
            coordinator.appliedVersion = version
        }

        if coordinator.lastWrapEnabled != wrapEnabled {
            coordinator.lastWrapEnabled = wrapEnabled
            applyWrap(textView, enabled: wrapEnabled)
        }

        applySearchHighlight(textView, matchRanges: matchRanges, currentMatchRange: currentMatchRange,
                              base: coordinator.baseAttributed ?? NSAttributedString(), coordinator: coordinator)

        coordinator.currentMatchRange = currentMatchRange
        coordinator.showsLineNumbers = showsLineNumbers
        coordinator.hexDividerOffsets = stream.hexDividerOffsets
        coordinator.relayout()

        if coordinator.lastScrollToken != scrollToken {
            coordinator.lastScrollToken = scrollToken
            if let range = currentMatchRange {
                scrollToMatch(range, in: textView)
            }
        }
    }

    private func applyWrap(_ tv: UITextView, enabled: Bool) {
        if enabled {
            tv.textContainer.widthTracksTextView = true
            tv.textContainer.size = CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)
        } else {
            tv.textContainer.widthTracksTextView = false
            tv.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        weak var textView: UITextView?
        weak var gutterView: AtlantisGutterView?
        weak var overlayView: AtlantisMatchOverlayView?
        weak var container: UIView?

        var appliedStream: AtlantisBodyStream?
        var appliedVersion = 0
        var baseAttributed: NSMutableAttributedString?
        var appliedMatchRanges: [NSRange] = []
        var appliedCurrentRange: NSRange?
        var currentMatchRange: NSRange?
        var lastWrapEnabled: Bool?
        var showsLineNumbers = true
        var lastScrollToken = 0
        var lastGutterDigitCount = 0
        var gutterWidth: CGFloat = AtlantisSyntaxTheme.gutterWidthFloor
        var lineStarts: [Int] = [0]
        var hexDividerOffsets: [CGFloat] = []

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            gutterView?.setNeedsDisplay()
            overlayView?.updateLayers()
        }

        /// Re-derives the gutter/text-view/overlay frames. Called from
        /// `updateUIView` on data changes and from the container's own
        /// `layoutSubviews` so rotation and wrap toggles never leave the ring
        /// clipped outside the overlay's bounds (B4-6).
        func relayout() {
            guard let textView = textView, let gutter = gutterView, let overlay = overlayView,
                  let container = container else { return }

            let digitCount = String(lineStarts.count).count
            if digitCount != lastGutterDigitCount {
                lastGutterDigitCount = digitCount
                let digitWidth = ("0" as NSString)
                    .size(withAttributes: [.font: AtlantisSyntaxTheme.gutterFont]).width
                gutterWidth = atlantisGutterWidth(digitCount: digitCount, digitWidth: digitWidth)
            }

            let effectiveGutterWidth = showsLineNumbers ? gutterWidth : 0
            let bounds = container.bounds
            gutter.isHidden = !showsLineNumbers
            gutter.frame = CGRect(x: 0, y: 0, width: effectiveGutterWidth, height: bounds.height)
            textView.frame = CGRect(x: effectiveGutterWidth, y: 0, width: bounds.width - effectiveGutterWidth, height: bounds.height)

            gutter.lineStarts = lineStarts
            gutter.currentMatchRange = currentMatchRange
            gutter.textView = textView
            gutter.setNeedsDisplay()

            overlay.currentMatchRange = currentMatchRange
            overlay.hexDividerOffsets = hexDividerOffsets
            overlay.textView = textView
            overlay.frame = CGRect(x: 0, y: 0, width: textView.contentSize.width, height: textView.contentSize.height)
            overlay.updateLayers()
        }
    }
}

/// Hosts the gutter/text-view/overlay layout — reruns it on every layout pass
/// (rotation, wrap toggle), not only when SwiftUI happens to call `updateUIView`
/// (B4-6).
private final class AtlantisCodeContainerView: UIView {
    var layoutHandler: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutHandler?()
    }
}

/// Draws only the line numbers whose fragments intersect the visible rect,
/// located by binary search over `lineStarts`. Redrawn on scroll — never a
/// full-document enumeration (perf contract rule 4). Wrapped continuation
/// fragments carry no number; the current match's line is accent semibold.
private final class AtlantisGutterView: UIView {
    weak var textView: UITextView?
    var lineStarts: [Int] = [0]
    var currentMatchRange: NSRange?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AtlantisSyntaxTheme.gutterFill
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let tv = textView, let layoutManager = tv.layoutManager as NSLayoutManager? else { return }
        let container = tv.textContainer
        let inset = tv.textContainerInset
        let visibleRect = tv.bounds.offsetBy(dx: -inset.left, dy: -inset.top)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)

        let currentLineIndex: Int? = currentMatchRange.map { atlantisLineIndex(for: $0.location, in: lineStarts) }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, fragGlyphRange, _ in
            var actualCharRange = NSRange(location: 0, length: 0)
            let charRange = layoutManager.characterRange(forGlyphRange: fragGlyphRange, actualGlyphRange: &actualCharRange)
            let lineIndex = atlantisLineIndex(for: charRange.location, in: self.lineStarts)
            guard self.lineStarts.indices.contains(lineIndex), self.lineStarts[lineIndex] == charRange.location else {
                return // wrapped continuation fragment — no number
            }

            let number = "\(lineIndex + 1)"
            let isCurrent = currentLineIndex == lineIndex
            let font = isCurrent ? AtlantisSyntaxTheme.gutterFontCurrent : AtlantisSyntaxTheme.gutterFont
            let color = isCurrent ? AtlantisSyntaxTheme.gutterTextCurrent : AtlantisSyntaxTheme.gutterText

            let localY = fragmentRect.minY + inset.top - tv.contentOffset.y
            let leading = AtlantisSyntaxTheme.gutterPaddingLeading
            let trailing = AtlantisSyntaxTheme.gutterPaddingTrailing
            let textRect = CGRect(x: leading, y: localY, width: self.bounds.width - leading - trailing, height: fragmentRect.height)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            (number as NSString).draw(in: textRect, withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        // Trailing hairline divider (B4-4, design §6.1).
        let dividerWidth = AtlantisSyntaxTheme.gutterDividerWidth
        AtlantisSyntaxTheme.gutterDivider.setFill()
        UIRectFill(CGRect(x: self.bounds.width - dividerWidth, y: 0, width: dividerWidth, height: self.bounds.height))
    }
}

/// Non-interactive overlay hosting the current-match ring (design §8). A subview
/// of the text view's own scrolling content, so it scrolls for free and needs no
/// per-frame offset math. Backed by three pinned `CAShapeLayer`s whose paths are
/// reassigned on current-match change — never a `draw(_:)` override, which would
/// force a document-height raster on every redraw (B4-2, perf contract 10a).
private final class AtlantisMatchOverlayView: UIView {
    weak var textView: UITextView?
    var currentMatchRange: NSRange?
    /// Hex-mode column divider x-offsets, relative to `canvasInset` — empty for
    /// every other mode (B-5, design §6.3).
    var hexDividerOffsets: [CGFloat] = []

    // No fill layer: the current match's background is already painted by the
    // `.backgroundColor` attribute on the text storage, which draws behind the
    // glyphs. An opaque overlay fill here would sit above the glyph drawing and
    // hide the matched text (B4-2 / B-2). Only what attributes cannot express —
    // the row tint and the ring stroke — is drawn at the layer level.
    private let tintLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let dividerLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = AtlantisSyntaxTheme.currentMatchRingWidth
        dividerLayer.fillColor = nil
        dividerLayer.lineWidth = AtlantisSyntaxTheme.hexColumnDividerWidth
        layer.addSublayer(tintLayer)
        layer.addSublayer(ringLayer)
        layer.addSublayer(dividerLayer)
        resolveColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayers()
    }

    // `CAShapeLayer.fillColor`/`.strokeColor` are `CGColor` — resolved once and
    // never re-resolved by CALayer. Re-assign them whenever the trait
    // collection's appearance changes so light↔dark toggles don't leave stale
    // colors on screen (B-3, design §8.6).
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            resolveColors()
            updateLayers()
        }
    }

    private func resolveColors() {
        tintLayer.fillColor = AtlantisSyntaxTheme.currentRowTint.resolvedColor(with: traitCollection).cgColor
        ringLayer.strokeColor = AtlantisSyntaxTheme.currentMatchRing.resolvedColor(with: traitCollection).cgColor
        dividerLayer.strokeColor = AtlantisSyntaxTheme.gutterDivider.resolvedColor(with: traitCollection).cgColor
    }

    func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Hex column dividers — fixed x-offsets computed once from the dump's
        // fixed-width fields, drawn full-height. Independent of the current
        // match, so this runs even when there is none (B-5).
        if let tv = textView, !hexDividerOffsets.isEmpty {
            let inset = tv.textContainerInset.left
            let dividerPath = CGMutablePath()
            for x in hexDividerOffsets {
                let lineX = inset + x
                dividerPath.move(to: CGPoint(x: lineX, y: 0))
                dividerPath.addLine(to: CGPoint(x: lineX, y: bounds.height))
            }
            dividerLayer.path = dividerPath
        } else {
            dividerLayer.path = nil
        }

        guard let tv = textView, let range = currentMatchRange, range.length > 0 else {
            tintLayer.path = nil
            ringLayer.path = nil
            return
        }
        let layoutManager = tv.layoutManager
        let container = tv.textContainer
        let inset = tv.textContainerInset
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

        let tintPath = CGMutablePath()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, _, _ in
            tintPath.addRect(fragmentRect.offsetBy(dx: inset.left, dy: inset.top))
        }

        // The ring — enclosing rect inset 0.75pt, stroked 1.5pt.
        let radius = AtlantisSyntaxTheme.matchCornerRadius
        let inset2 = AtlantisSyntaxTheme.currentMatchRingInset
        let ringPath = CGMutablePath()

        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                               withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: container) { enclosingRect, _ in
            let r = enclosingRect.offsetBy(dx: inset.left, dy: inset.top)
            let ringRect = r.insetBy(dx: inset2, dy: inset2)
            let ringRadius = max(0, radius - inset2)
            ringPath.addPath(CGPath(roundedRect: ringRect, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil))
        }

        tintLayer.path = tintPath
        ringLayer.path = ringPath
    }
}

private func scrollToMatch(_ range: NSRange, in tv: UITextView) {
    let layoutManager = tv.layoutManager
    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
    rect = rect.offsetBy(dx: tv.textContainerInset.left, dy: tv.textContainerInset.top)

    let viewportHeight = tv.bounds.height
    guard viewportHeight > 0 else { return }
    var targetY = rect.minY - viewportHeight * AtlantisSyntaxTheme.scrollToMatchFraction
    let maxY = max(0, tv.contentSize.height - viewportHeight)
    targetY = max(0, min(targetY, maxY))
    tv.setContentOffset(CGPoint(x: tv.contentOffset.x, y: targetY), animated: true)
}

private func applySearchHighlight(_ tv: UITextView, matchRanges: [NSRange], currentMatchRange: NSRange?,
                                   base: NSAttributedString, coordinator: _Representable.Coordinator) {
    let matchesChanged = matchRanges != coordinator.appliedMatchRanges
    let currentChanged = currentMatchRange != coordinator.appliedCurrentRange
    guard matchesChanged || currentChanged else { return }

    let storage = tv.textStorage
    storage.beginEditing()

    if matchesChanged {
        for r in coordinator.appliedMatchRanges where NSMaxRange(r) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: r)
        }
    }

    // When the match set changes, the old current range is either gone or no
    // longer a match — it must not be repainted with `matchBackground` here,
    // since it is not written back into `appliedMatchRanges` and nothing would
    // ever clear it again (B4-1). Only repaint it as a plain match when the
    // match set itself is unchanged (i.e. just stepping to a new current match
    // within the same results); either way its forced foreground is restored.
    if let old = coordinator.appliedCurrentRange, old != currentMatchRange, NSMaxRange(old) <= storage.length {
        if !matchesChanged {
            storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.matchBackground, range: old)
        }
        base.enumerateAttribute(.foregroundColor, in: old, options: []) { value, subrange, _ in
            if let value = value {
                storage.addAttribute(.foregroundColor, value: value, range: subrange)
            } else {
                storage.removeAttribute(.foregroundColor, range: subrange)
            }
        }
    }

    if matchesChanged {
        for r in matchRanges where NSMaxRange(r) <= storage.length {
            storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.matchBackground, range: r)
        }
    }

    if let new = currentMatchRange, new != coordinator.appliedCurrentRange, NSMaxRange(new) <= storage.length {
        storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.currentMatchBackground, range: new)
        storage.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.currentMatchForeground, range: new)
    }

    storage.endEditing()
    coordinator.appliedMatchRanges = matchRanges
    coordinator.appliedCurrentRange = currentMatchRange
}

#elseif os(macOS)
import AppKit

private struct _Representable: NSViewRepresentable {
    let stream: AtlantisBodyStream
    let version: Int
    var matchRanges: [NSRange]
    var currentMatchRange: NSRange?
    var wrapEnabled: Bool
    var showsLineNumbers: Bool
    var scrollToken: Int

    func makeNSView(context: Context) -> NSView {
        let coordinator = context.coordinator
        let container = AtlantisCodeContainerView()
        container.layoutHandler = { [weak coordinator] in coordinator?.relayout() }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager() // TextKit 1
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        let inset = AtlantisSyntaxTheme.canvasInset
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: inset, height: inset)
        textContainer.lineFragmentPadding = AtlantisSyntaxTheme.lineFragmentPadding

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        let gutter = AtlantisGutterView()
        let overlay = AtlantisMatchOverlayView(frame: .zero)
        overlay.autoresizingMask = [.width, .height]
        textView.addSubview(overlay)

        container.addSubview(scrollView)
        container.addSubview(gutter)

        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.gutterView = gutter
        coordinator.overlayView = overlay
        coordinator.container = container

        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.boundsDidChange),
                                                 name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView,
              let storage = textView.textStorage else { return }

        if coordinator.appliedStream !== stream {
            coordinator.appliedStream = stream
            coordinator.appliedVersion = 0
            coordinator.baseAttributed = NSMutableAttributedString()
            coordinator.lineStarts = []
            storage.setAttributedString(NSAttributedString())
            coordinator.appliedMatchRanges = []
            coordinator.appliedCurrentRange = nil
        }

        if version > coordinator.appliedVersion {
            let base = coordinator.baseAttributed ?? NSMutableAttributedString()
            storage.beginEditing()
            for i in coordinator.appliedVersion..<version where i < stream.chunks.count {
                let chunk = stream.chunks[i]
                storage.append(chunk.attributed)
                base.append(chunk.attributed)
                coordinator.lineStarts.append(contentsOf: chunk.lineStarts)
            }
            storage.endEditing()
            coordinator.baseAttributed = base
            coordinator.appliedVersion = version
        }

        if coordinator.lastWrapEnabled != wrapEnabled {
            coordinator.lastWrapEnabled = wrapEnabled
            applyWrap(textView, enabled: wrapEnabled)
        }

        applySearchHighlight(textView, matchRanges: matchRanges, currentMatchRange: currentMatchRange,
                              base: coordinator.baseAttributed ?? NSAttributedString(), coordinator: coordinator)

        coordinator.currentMatchRange = currentMatchRange
        coordinator.showsLineNumbers = showsLineNumbers
        coordinator.hexDividerOffsets = stream.hexDividerOffsets
        coordinator.relayout()

        if coordinator.lastScrollToken != scrollToken, let scrollView = coordinator.scrollView {
            coordinator.lastScrollToken = scrollToken
            if let range = currentMatchRange {
                scrollToMatch(range, in: textView, scrollView: scrollView)
            }
        }
    }

    private func applyWrap(_ tv: NSTextView, enabled: Bool) {
        guard let container = tv.textContainer else { return }
        if enabled {
            container.widthTracksTextView = true
            tv.isHorizontallyResizable = false
            container.containerSize = NSSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)
        } else {
            container.widthTracksTextView = false
            tv.isHorizontallyResizable = true
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var gutterView: AtlantisGutterView?
        weak var overlayView: AtlantisMatchOverlayView?
        weak var container: NSView?

        var appliedStream: AtlantisBodyStream?
        var appliedVersion = 0
        var baseAttributed: NSMutableAttributedString?
        var appliedMatchRanges: [NSRange] = []
        var appliedCurrentRange: NSRange?
        var currentMatchRange: NSRange?
        var lastWrapEnabled: Bool?
        var showsLineNumbers = true
        var lastScrollToken = 0
        var lastGutterDigitCount = 0
        var gutterWidth: CGFloat = AtlantisSyntaxTheme.gutterWidthFloor
        var lineStarts: [Int] = [0]
        var hexDividerOffsets: [CGFloat] = []

        @objc func boundsDidChange() {
            gutterView?.needsDisplay = true
            overlayView?.updateLayers()
        }

        /// Re-derives the gutter/text-view/overlay frames on every layout pass —
        /// not only when SwiftUI happens to call `updateNSView` (B4-6).
        func relayout() {
            guard let textView = textView, let scrollView = scrollView, let gutter = gutterView,
                  let overlay = overlayView, let container = container else { return }

            let digitCount = String(lineStarts.count).count
            if digitCount != lastGutterDigitCount {
                lastGutterDigitCount = digitCount
                let digitWidth = ("0" as NSString)
                    .size(withAttributes: [.font: AtlantisSyntaxTheme.gutterFont]).width
                gutterWidth = atlantisGutterWidth(digitCount: digitCount, digitWidth: digitWidth)
            }

            let effectiveGutterWidth = showsLineNumbers ? gutterWidth : 0
            let bounds = container.bounds
            gutter.isHidden = !showsLineNumbers
            gutter.frame = CGRect(x: 0, y: 0, width: effectiveGutterWidth, height: bounds.height)
            scrollView.frame = CGRect(x: effectiveGutterWidth, y: 0, width: bounds.width - effectiveGutterWidth, height: bounds.height)

            gutter.lineStarts = lineStarts
            gutter.currentMatchRange = currentMatchRange
            gutter.nsTextView = textView
            gutter.nsScrollView = scrollView
            gutter.needsDisplay = true

            overlay.currentMatchRange = currentMatchRange
            overlay.hexDividerOffsets = hexDividerOffsets
            overlay.nsTextView = textView
            overlay.frame = textView.bounds
            overlay.updateLayers()
        }
    }
}

/// Hosts the gutter/text-view/overlay layout — reruns it on every layout pass
/// (window resize, wrap toggle), not only when SwiftUI happens to call
/// `updateNSView` (B4-6).
private final class AtlantisCodeContainerView: NSView {
    var layoutHandler: (() -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?()
    }

    // `layout()` only fires for views under Auto Layout / layer-backed
    // invalidation; this container is frame-sized directly by SwiftUI, so
    // `setFrameSize` is the reliable hook for window resize (B4-6).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutHandler?()
    }
}

private final class AtlantisGutterView: NSView {
    weak var nsTextView: NSTextView?
    weak var nsScrollView: NSScrollView?
    var lineStarts: [Int] = [0]
    var currentMatchRange: NSRange?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        AtlantisSyntaxTheme.gutterFill.setFill()
        dirtyRect.fill()

        guard let tv = nsTextView, let layoutManager = tv.layoutManager, let container = tv.textContainer,
              let scrollView = nsScrollView else { return }
        let inset = tv.textContainerInset
        let visibleRect = scrollView.contentView.bounds
        let containerVisibleRect = visibleRect.offsetBy(dx: -inset.width, dy: -inset.height)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerVisibleRect, in: container)

        let currentLineIndex: Int? = currentMatchRange.map { atlantisLineIndex(for: $0.location, in: lineStarts) }
        let contentOffsetY = scrollView.contentView.bounds.origin.y

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, fragGlyphRange, _ in
            var actualCharRange = NSRange(location: 0, length: 0)
            let charRange = layoutManager.characterRange(forGlyphRange: fragGlyphRange, actualGlyphRange: &actualCharRange)
            let lineIndex = atlantisLineIndex(for: charRange.location, in: self.lineStarts)
            guard self.lineStarts.indices.contains(lineIndex), self.lineStarts[lineIndex] == charRange.location else {
                return
            }

            let number = "\(lineIndex + 1)"
            let isCurrent = currentLineIndex == lineIndex
            let font = isCurrent ? AtlantisSyntaxTheme.gutterFontCurrent : AtlantisSyntaxTheme.gutterFont
            let color = isCurrent ? AtlantisSyntaxTheme.gutterTextCurrent : AtlantisSyntaxTheme.gutterText

            let localY = fragmentRect.minY + inset.height - contentOffsetY
            let leading = AtlantisSyntaxTheme.gutterPaddingLeading
            let trailing = AtlantisSyntaxTheme.gutterPaddingTrailing
            let textRect = CGRect(x: leading, y: localY, width: self.bounds.width - leading - trailing, height: fragmentRect.height)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            (number as NSString).draw(in: textRect, withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        // Trailing hairline divider (B4-4, design §6.1).
        let dividerWidth = AtlantisSyntaxTheme.gutterDividerWidth
        AtlantisSyntaxTheme.gutterDivider.setFill()
        CGRect(x: self.bounds.width - dividerWidth, y: 0, width: dividerWidth, height: self.bounds.height).fill()
    }
}

/// Backed by three pinned `CAShapeLayer`s whose paths are reassigned on
/// current-match change — never a `draw(_:)` override (B4-2, perf contract 10a).
private final class AtlantisMatchOverlayView: NSView {
    weak var nsTextView: NSTextView?
    var currentMatchRange: NSRange?
    /// Hex-mode column divider x-offsets, relative to `canvasInset` — empty for
    /// every other mode (B-5, design §6.3).
    var hexDividerOffsets: [CGFloat] = []

    // No fill layer: the current match's background is already painted by the
    // `.backgroundColor` attribute on the text storage, which draws behind the
    // glyphs. An opaque overlay fill here would sit above the glyph drawing and
    // hide the matched text (B4-2 / B-2). Only what attributes cannot express —
    // the row tint and the ring stroke — is drawn at the layer level.
    private let tintLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let dividerLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = AtlantisSyntaxTheme.currentMatchRingWidth
        dividerLayer.fillColor = nil
        dividerLayer.lineWidth = AtlantisSyntaxTheme.hexColumnDividerWidth
        layer?.addSublayer(tintLayer)
        layer?.addSublayer(ringLayer)
        layer?.addSublayer(dividerLayer)
        resolveColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateLayers()
    }

    // `CAShapeLayer.fillColor`/`.strokeColor` are `CGColor` — resolved once and
    // never re-resolved by CALayer. Re-assign them whenever the effective
    // appearance changes so light↔dark toggles don't leave stale colors on
    // screen (B-3, design §8.6).
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
        updateLayers()
    }

    private func resolveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintLayer.fillColor = AtlantisSyntaxTheme.currentRowTint.cgColor
            ringLayer.strokeColor = AtlantisSyntaxTheme.currentMatchRing.cgColor
            dividerLayer.strokeColor = AtlantisSyntaxTheme.gutterDivider.cgColor
        }
    }

    func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Hex column dividers — fixed x-offsets computed once from the dump's
        // fixed-width fields, drawn full-height. Independent of the current
        // match, so this runs even when there is none (B-5).
        if let tv = nsTextView, !hexDividerOffsets.isEmpty {
            let inset = tv.textContainerInset.width
            let dividerPath = CGMutablePath()
            for x in hexDividerOffsets {
                let lineX = inset + x
                dividerPath.move(to: CGPoint(x: lineX, y: 0))
                dividerPath.addLine(to: CGPoint(x: lineX, y: bounds.height))
            }
            dividerLayer.path = dividerPath
        } else {
            dividerLayer.path = nil
        }

        guard let tv = nsTextView, let layoutManager = tv.layoutManager, let container = tv.textContainer,
              let range = currentMatchRange, range.length > 0 else {
            tintLayer.path = nil
            ringLayer.path = nil
            return
        }
        let inset = tv.textContainerInset
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

        let tintPath = CGMutablePath()
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, _, _ in
            tintPath.addRect(fragmentRect.offsetBy(dx: inset.width, dy: inset.height))
        }

        let radius = AtlantisSyntaxTheme.matchCornerRadius
        let inset2 = AtlantisSyntaxTheme.currentMatchRingInset
        let ringPath = CGMutablePath()

        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                               withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                               in: container) { enclosingRect, _ in
            let r = enclosingRect.offsetBy(dx: inset.width, dy: inset.height)
            let ringRect = r.insetBy(dx: inset2, dy: inset2)
            let ringRadius = max(0, radius - inset2)
            ringPath.addPath(CGPath(roundedRect: ringRect, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil))
        }

        tintLayer.path = tintPath
        ringLayer.path = ringPath
    }
}

private func scrollToMatch(_ range: NSRange, in tv: NSTextView, scrollView: NSScrollView) {
    guard let layoutManager = tv.layoutManager, let container = tv.textContainer else { return }
    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
    rect = rect.offsetBy(dx: tv.textContainerInset.width, dy: tv.textContainerInset.height)

    let viewportHeight = scrollView.contentView.bounds.height
    guard viewportHeight > 0 else { return }
    var targetY = rect.minY - viewportHeight * AtlantisSyntaxTheme.scrollToMatchFraction
    let maxY = max(0, tv.bounds.height - viewportHeight)
    targetY = max(0, min(targetY, maxY))
    scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY))
    scrollView.reflectScrolledClipView(scrollView.contentView)
}

private func applySearchHighlight(_ tv: NSTextView, matchRanges: [NSRange], currentMatchRange: NSRange?,
                                   base: NSAttributedString, coordinator: _Representable.Coordinator) {
    guard let storage = tv.textStorage else { return }
    let matchesChanged = matchRanges != coordinator.appliedMatchRanges
    let currentChanged = currentMatchRange != coordinator.appliedCurrentRange
    guard matchesChanged || currentChanged else { return }

    storage.beginEditing()

    if matchesChanged {
        for r in coordinator.appliedMatchRanges where NSMaxRange(r) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: r)
        }
    }

    if let old = coordinator.appliedCurrentRange, old != currentMatchRange, NSMaxRange(old) <= storage.length {
        if !matchesChanged {
            storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.matchBackground, range: old)
        }
        base.enumerateAttribute(.foregroundColor, in: old, options: []) { value, subrange, _ in
            if let value = value {
                storage.addAttribute(.foregroundColor, value: value, range: subrange)
            } else {
                storage.removeAttribute(.foregroundColor, range: subrange)
            }
        }
    }

    if matchesChanged {
        for r in matchRanges where NSMaxRange(r) <= storage.length {
            storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.matchBackground, range: r)
        }
    }

    if let new = currentMatchRange, new != coordinator.appliedCurrentRange, NSMaxRange(new) <= storage.length {
        storage.addAttribute(.backgroundColor, value: AtlantisSyntaxTheme.currentMatchBackground, range: new)
        storage.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.currentMatchForeground, range: new)
    }

    storage.endEditing()
    coordinator.appliedMatchRanges = matchRanges
    coordinator.appliedCurrentRange = currentMatchRange
}
#endif
#endif

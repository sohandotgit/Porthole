//
//  AtlantisBodyViewerView.swift
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

/// `AtlantisViewerSettings.autoRenderLimitBytes` (design §6.2, tokens.md §9). No
/// settings screen ships this session — this is the only knob, and it is read
/// directly by the gate predicate and printed by the gate footnote.
enum AtlantisViewerSettings {
    @AppStorage("AtlantisViewerSettings.autoRenderLimitBytes")
    static var autoRenderLimitBytes: Int = 65_536
}

/// Off-main-thread intermediate for the current `(mode, asciiVisible)` build —
/// full text, its once-built fully token-colored attributed form, the
/// `lineStarts` table the gutter and stats line share, and hex divider
/// offsets. Chunked into an `AtlantisBodyStream` for progressive display
/// (docs/plan-progressive-body-render.md Part 1).
private struct AtlantisBodyStreamPrepared {
    let text: String
    let attributed: NSAttributedString
    let lineStarts: [Int]
    /// Hex-mode column divider x-offsets (offset|bytes, bytes|ASCII), relative to
    /// `canvasInset` — empty for every other mode (B-5, design §6.3). Computed
    /// once alongside the hex dump build from the monospace advance widths of
    /// its fixed-width fields, never re-measured per frame.
    let hexDividerOffsets: [CGFloat]
}

private struct AtlantisBodyBuildKey: Hashable {
    let mode: AtlantisBodyMode
    let asciiVisible: Bool
}

/// `.task(id:)` change signal for `streamIfNeeded` — a superset of
/// `AtlantisBodyBuildKey` (the cache key) that also re-fires the build task when
/// classification finishes landing, gating changes, or Dynamic Type changes.
///
/// Must include `isGated`: without it, classification landing while gated
/// fires this task once, which hits its own `guard !isGated` and clears
/// `stream` to nil — then revealing the body (`revealed = true`) changes only
/// `isGated`, which this key used to omit, so the task never re-fired and the
/// canvas stayed permanently blank (Part 0 root-cause fix).
private struct AtlantisBodyRebuildKey: Equatable {
    let mode: AtlantisBodyMode
    let asciiVisible: Bool
    let isClassifying: Bool
    let isGated: Bool
    let sizeCategory: String
}

/// `.task(id:)` signal for the JSON tree build — re-fires on a new body, a
/// mode switch into/out of `.tree`, classification landing, or the gate
/// toggling, so `buildTreeIfNeeded` can both parse-once-per-body and
/// recompute search state whenever tree mode becomes active again.
private struct AtlantisTreeBuildKey: Equatable {
    let data: Data
    let mode: AtlantisBodyMode
    let isGated: Bool
    let isClassifying: Bool
}

/// The body viewer screen (design/body-viewer-ui-v2.md §2-§6): meta card, control
/// strip, inline search row, canvas card, and the four states (rendered / gated /
/// hex / empty). Composes `AtlantisCodeTextView` — never reimplements TextKit.
struct AtlantisBodyViewerView: View {
    let title: String
    let data: Data
    let contentType: String?
    let method: String
    let side: AtlantisBodySide
    let statusCode: Int?

    @State private var classification: AtlantisBodyClassification
    @State private var mode: AtlantisBodyMode
    @State private var revealed = false
    @State private var wrapEnabled = true
    @State private var lineNumbersOn = true
    @State private var asciiVisible = true
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var matches: [NSRange] = []
    @State private var currentMatchIndex = 0
    @State private var scrollToken = 0
    @State private var copiedChip: AtlantisBodyChip?
    @State private var stream: AtlantisBodyStream?
    @State private var builtCache: [AtlantisBodyBuildKey: AtlantisBodyStream] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var copyResetTask: Task<Void, Never>?
    @State private var imageScale: CGFloat = 1

    @State private var jsonTreeRoot: AtlantisJSONValue?
    @State private var treeExpandedPaths: Set<AtlantisJSONPath> = []
    @State private var treeRows: [AtlantisJSONTreeRow] = []
    @State private var treeMatches: [AtlantisJSONPath] = []
    @State private var treeCurrentMatchIndex = 0

    /// `true` until the off-main classification for the current `data` has
    /// landed (B5-2). The init below only does an O(1) empty check — the real
    /// `AtlantisBodyClassifier.classify` (JSON parsing, pretty-printing, the
    /// UTF-8 scan) never runs on the main thread or inside a SwiftUI `init`.
    @State private var isClassifying = true

    init(title: String, data: Data, contentType: String?, method: String,
         side: AtlantisBodySide, statusCode: Int?) {
        self.title = title
        self.data = data
        self.contentType = contentType
        self.method = method
        self.side = side
        self.statusCode = statusCode
        let placeholder = Self.placeholderClassification(data: data)
        _classification = State(initialValue: placeholder)
        let options = AtlantisBodyMode.options(for: placeholder.kind)
        _mode = State(initialValue: options.defaultMode ?? .pretty)
    }

    /// A cheap stand-in used only until the real classification lands
    /// off-main — `.empty` when there are no bytes (so the empty state never
    /// flashes wrong), `.text` otherwise (renders as plain, unhighlighted text
    /// for a moment rather than misrendering as `.empty` or `.image`).
    private static func placeholderClassification(data: Data) -> AtlantisBodyClassification {
        guard !data.isEmpty else {
            return AtlantisBodyClassification(kind: .empty, byteCount: 0, prettyText: nil, rawText: nil,
                                               prettyLineCount: 0, rawLineCount: 0,
                                               utf8InvalidByteCount: nil, utf8FirstInvalidOffset: nil,
                                               binaryLossyText: nil, binaryLossyLineCount: 0)
        }
        return AtlantisBodyClassification(kind: .text, byteCount: data.count, prettyText: nil, rawText: nil,
                                           prettyLineCount: 0, rawLineCount: 0,
                                           utf8InvalidByteCount: nil, utf8FirstInvalidOffset: nil,
                                           binaryLossyText: nil, binaryLossyLineCount: 0)
    }

    @MainActor
    private func classifyIfNeeded() async {
        let contentType = self.contentType
        let data = self.data
        let result = await Task.detached(priority: .userInitiated) {
            AtlantisBodyClassifier.classify(data, contentType: contentType)
        }.value
        guard !Task.isCancelled else { return }
        classification = result
        isClassifying = false
        builtCache = [:]
        stream = nil
        jsonTreeRoot = nil
        treeExpandedPaths = []
        treeRows = []
        treeMatches = []
        treeCurrentMatchIndex = 0
        let options = AtlantisBodyMode.options(for: result.kind)
        mode = options.defaultMode ?? .pretty
    }

    private var kind: AtlantisBodyClassifiedKind { classification.kind }

    private var optionMatrix: (options: [AtlantisBodyMode], defaultMode: AtlantisBodyMode?, disabled: Set<AtlantisBodyMode>, showsPicker: Bool) {
        AtlantisBodyMode.options(for: kind)
    }

    /// Design §6.2 conditions the gate on byte count alone; hex has its own
    /// independent 1 MB cap (§1 contradiction 3), but nothing else should render
    /// an ungated multi-megabyte body — `.image` is included so a huge image
    /// body isn't decoded with no cap of any kind (B5-12).
    private var isGated: Bool {
        guard mode == .pretty || mode == .tree || mode == .raw || mode == .text || mode == .image else { return false }
        return AtlantisBodyGate.isGated(byteCount: classification.byteCount,
                                         limit: AtlantisViewerSettings.autoRenderLimitBytes,
                                         revealed: revealed)
    }

    /// The raw text used by Raw mode — the classifier's `rawText` for every kind
    /// except `.binary`, where it is the lossy UTF-8 decode computed once by
    /// `classify` (design §1.1, B-6) — never a per-render main-thread re-decode
    /// of the full payload.
    private var rawModeText: String {
        classification.rawText ?? classification.binaryLossyText ?? ""
    }

    private var rawModeLineCount: Int {
        classification.rawText != nil ? classification.rawLineCount : classification.binaryLossyLineCount
    }

    /// The full text for the current mode — what Copy copies (design §5.3).
    /// Always the whole payload, never the streamed-so-far prefix, even while
    /// `stream` is still loading.
    private var currentDisplayText: String {
        switch mode {
        case .pretty, .tree: return classification.prettyText ?? ""
        case .raw: return rawModeText
        case .text: return classification.rawText ?? ""
        case .hex:
            // The hex dump for the current `(mode, asciiVisible)` is already
            // built off-main by `streamIfNeeded` — reuse its full text rather
            // than re-running `AtlantisHexDump.build` synchronously here on
            // every access (Copy, search recompute) (B5-3).
            return stream?.fullText ?? ""
        case .image: return ""
        }
    }

    /// The text search scoping should read: while `stream` is still loading,
    /// only what has actually been appended to `textStorage` so far — reading
    /// the full text here would produce match ranges TextKit can't yet locate,
    /// and stepping to one would scroll to a range that doesn't exist in the
    /// canvas yet (docs/plan-progressive-body-render.md Part 3).
    private var searchScopedText: String {
        if let stream = stream, !stream.isComplete { return stream.loadedText }
        return currentDisplayText
    }

    private var statsLineText: String {
        if isGated {
            // `.image` has no lines — reporting bytes only avoids consulting
            // `rawModeLineCount`, which would otherwise force a full-payload
            // decode and line scan on the main thread while the gate is on
            // screen (B-6).
            if kind == .image {
                return AtlantisBodyStats.statsLine(.gatedImage(byteCount: classification.byteCount))
            }
            return AtlantisBodyStats.statsLine(.gated(byteCount: classification.byteCount, lineCount: rawModeLineCount))
        }
        switch mode {
        case .pretty, .tree:
            return AtlantisBodyStats.statsLine(.pretty(byteCount: classification.byteCount, lineCount: classification.prettyLineCount))
        case .raw:
            return AtlantisBodyStats.statsLine(.raw(byteCount: classification.byteCount, lineCount: rawModeLineCount))
        case .text:
            return AtlantisBodyStats.statsLine(.text(byteCount: classification.byteCount, lineCount: rawModeLineCount))
        case .hex:
            return AtlantisBodyStats.statsLine(.hex(byteCount: classification.byteCount))
        case .image:
            let size = atlantisImageSize(data)
            return AtlantisBodyStats.statsLine(.image(badge: kind.badge, width: Int(size.width), height: Int(size.height),
                                                       byteCount: classification.byteCount))
        }
    }

    /// From the classification, computed once by `classify` (B5-5) — never a
    /// per-render re-scan of `data`.
    private var utf8Diagnosis: (invalidByteCount: Int, firstInvalidOffset: Int)? {
        classification.utf8Diagnosis
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    @Environment(\.sizeCategory) private var sizeCategory
    #endif

    var body: some View {
        Group {
            if kind == .empty || isGated {
                // Only the gate and empty states scroll their own content —
                // the canvas owns its scroll for the rendered/hex states
                // (B5-1, perf contract rule 3).
                ScrollView { content }
            } else {
                content
            }
        }
        .background(Color(AtlantisSyntaxTheme.pageFill))
        .navigationTitle(title)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) { ellipsisMenu }
            #else
            ToolbarItem { ellipsisMenu }
            #endif
        }
        .task(id: data) {
            await classifyIfNeeded()
        }
        .task(id: AtlantisBodyRebuildKey(mode: mode, asciiVisible: asciiVisible, isClassifying: isClassifying,
                                          isGated: isGated, sizeCategory: sizeCategoryToken)) {
            await streamIfNeeded()
        }
        .task(id: AtlantisTreeBuildKey(data: data, mode: mode, isGated: isGated, isClassifying: isClassifying)) {
            await buildTreeIfNeeded()
        }
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: AtlantisSyntaxTheme.searchDebounceNanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    debouncedQuery = newValue
                    if mode == .tree {
                        recomputeTreeMatches()
                    } else {
                        recomputeMatches()
                    }
                }
            }
        }
    }

    /// Included in the rebuild key so a Dynamic Type change re-triggers the
    /// build task and the canvas picks up the newly-scaled fonts (B4-5, design
    /// §8.6) — `AtlantisSyntaxTheme`'s fonts are resolved per-access, not cached,
    /// but the already-built `NSAttributedString` still needs to be redone.
    private var sizeCategoryToken: String {
        #if os(iOS) || targetEnvironment(macCatalyst)
        return "\(sizeCategory)"
        #else
        return "macOS"
        #endif
    }

    @ViewBuilder
    private var ellipsisMenu: some View {
        Menu {
            Button("Copy") { copy(currentDisplayText) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: AtlantisSyntaxTheme.navEllipsisSize, weight: .regular))
                .foregroundColor(kind == .empty ? Color(AtlantisSyntaxTheme.labelDisabled) : Color(AtlantisSyntaxTheme.accent))
        }
        .disabled(kind == .empty)
    }

    @ViewBuilder
    private var content: some View {
        if kind == .empty {
            AtlantisBodyEmptyStateView(method: method, side: side, statusCode: statusCode)
        } else {
            VStack(alignment: .leading, spacing: mode == .hex ? AtlantisSyntaxTheme.cardGapHex : AtlantisSyntaxTheme.cardGap) {
                AtlantisBodyMetaCard(kind: kind, contentType: contentType, statsLine: statsLineText)

                if isGated {
                    gateCard
                } else {
                    // Meta card → banner → control strip → canvas (design §6.3);
                    // the banner must land above the control strip, not between
                    // the picker and the canvas (B5-14).
                    if mode == .hex, let diag = utf8Diagnosis {
                        AtlantisBodyUTF8Banner(invalidByteCount: diag.invalidByteCount, firstInvalidOffset: diag.firstInvalidOffset)
                    }
                    controlStrip
                    if mode.showsSearchRow {
                        searchRow
                    }
                    if canvasState == .streaming {
                        AtlantisBodyStreamBanner(loadedUTF16: stream?.loadedUTF16 ?? 0, totalUTF16: stream?.totalUTF16 ?? 0)
                    }
                    canvasCard
                }
            }
            .padding(.top, AtlantisSyntaxTheme.contentColumnPaddingTop)
            .padding(.horizontal, AtlantisSyntaxTheme.contentColumnPaddingHorizontal)
            .padding(.bottom, isGated ? AtlantisSyntaxTheme.gateContentBottomPadding : 0)
            .frame(maxHeight: isGated ? nil : .infinity)
        }
    }

    // MARK: - Control strip

    @ViewBuilder
    private var controlStrip: some View {
        HStack(spacing: AtlantisSyntaxTheme.controlStripGap) {
            if optionMatrix.showsPicker {
                AtlantisBodySegmentedPicker(mode: $mode, options: optionMatrix.options, disabled: optionMatrix.disabled)
            }
            HStack(spacing: AtlantisSyntaxTheme.chipGap) {
                ForEach(AtlantisBodyMode.chips(for: mode), id: \.self) { chip in
                    chipView(chip)
                }
            }
        }
    }

    @ViewBuilder
    private func chipView(_ chip: AtlantisBodyChip) -> some View {
        let isCopied = copiedChip == chip
        switch chip {
        case .wrap:
            AtlantisBodyIconChip(isActive: wrapEnabled, isCopied: false,
                                  help: "Wrap lines", accessibilityLabel: "Toggle line wrapping") {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: AtlantisSyntaxTheme.wrapGlyphSize, weight: .regular))
            } action: { wrapEnabled.toggle() }
        case .lineNumbers:
            AtlantisBodyIconChip(isActive: lineNumbersOn, isCopied: false,
                                  help: "Line numbers", accessibilityLabel: "Toggle line numbers") {
                glyphPair("1", "2", font: AtlantisSyntaxTheme.chipGlyphFont)
            } action: { lineNumbersOn.toggle() }
        case .asciiPane:
            AtlantisBodyIconChip(isActive: asciiVisible, isCopied: false,
                                  help: "ASCII pane", accessibilityLabel: "Toggle ASCII pane") {
                glyphPair("A", "S", font: AtlantisSyntaxTheme.chipGlyphFontSmall)
            } action: { asciiVisible.toggle() }
        case .copy:
            AtlantisBodyIconChip(isActive: false, isCopied: isCopied,
                                  help: "Copy", accessibilityLabel: "Copy body") {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: AtlantisSyntaxTheme.copyGlyphSize, weight: .regular))
            } action: { performCopy() }
        case .expandCollapseAll:
            AtlantisBodyIconChip(isActive: false, isCopied: false,
                                  help: "Expand/collapse all", accessibilityLabel: "Expand or collapse all nodes") {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: AtlantisSyntaxTheme.treeToolbarGlyphSize, weight: .regular))
            } action: { toggleExpandCollapseAll() }
        }
    }

    private func glyphPair(_ a: String, _ b: String, font: AtlantisSyntaxTheme.PlatformFont) -> some View {
        Text(a + "\u{200A}" + b).font(Font(font))
    }

    private func performCopy() {
        copy(currentDisplayText)
        copyResetTask?.cancel()
        copiedChip = .copy
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(AtlantisSyntaxTheme.copyConfirmationDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { copiedChip = nil }
        }
    }

    private func copy(_ string: String) {
        #if os(iOS) || targetEnvironment(macCatalyst)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    // MARK: - Search row

    @ViewBuilder
    private var searchRow: some View {
        if mode == .tree {
            AtlantisBodySearchRow(query: $query, matchCount: treeMatches.count, currentMatchIndex: treeCurrentMatchIndex,
                                   onPrev: { stepTree(-1) }, onNext: { stepTree(1) })
        } else {
            AtlantisBodySearchRow(query: $query, matchCount: matches.count, currentMatchIndex: currentMatchIndex,
                                   onPrev: { step(-1) }, onNext: { step(1) })
        }
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + delta + matches.count) % matches.count
        scrollToken += 1
    }

    private func recomputeMatches() {
        matches = AtlantisBodySearch.nsMatchRanges(in: searchScopedText, query: debouncedQuery)
        currentMatchIndex = 0
        scrollToken += 1
    }

    // MARK: - Canvas

    /// Canvas state machine (docs/plan-progressive-body-render.md Part 3),
    /// replacing the old `built == nil` blank-forever branch.
    private enum AtlantisBodyCanvasState {
        case idle          // gated / empty / classifying — canvasCard isn't reached for these
        case preparing     // build started, chunk 0 not in yet
        case streaming     // chunk 0..n applied, incomplete
        case complete
    }

    private var canvasState: AtlantisBodyCanvasState {
        guard !isGated, kind != .empty, !isClassifying else { return .idle }
        guard let stream = stream else { return .preparing }
        if stream.isComplete { return .complete }
        return stream.version == 0 ? .preparing : .streaming
    }

    @ViewBuilder
    private var canvasCard: some View {
        if mode == .image {
            AtlantisBodyImageView(data: data, scale: $imageScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(AtlantisSyntaxTheme.cardFill))
                .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
        } else if mode == .tree {
            if jsonTreeRoot != nil {
                let currentMatch = treeMatches.indices.contains(treeCurrentMatchIndex) ? treeMatches[treeCurrentMatchIndex] : nil
                AtlantisJSONTreeView(rows: treeRows, matchedPaths: Set(treeMatches), currentMatchPath: currentMatch,
                                     scrollToken: scrollToken, onToggle: toggleTreeNode)
                    .background(Color(AtlantisSyntaxTheme.cardFill))
                    .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                preparingCard
            }
        } else {
            switch canvasState {
            case .preparing, .idle:
                preparingCard
            case .streaming, .complete:
                if let stream = stream {
                    let currentRange = matches.indices.contains(currentMatchIndex) ? matches[currentMatchIndex] : nil
                    AtlantisCodeTextView(stream: stream, version: stream.version,
                                          matchRanges: matches, currentMatchRange: currentRange,
                                          wrapEnabled: mode == .hex ? false : wrapEnabled,
                                          showsLineNumbers: mode == .hex ? false : lineNumbersOn,
                                          scrollToken: scrollToken)
                        .background(Color(AtlantisSyntaxTheme.cardFill))
                        .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    preparingCard
                }
            }
        }
    }

    /// Spinner + byte count, centered in the card — shown while the build has
    /// started but no chunk has landed yet (design intent: something
    /// immediately visible other than a blank rectangle).
    private var preparingCard: some View {
        VStack(spacing: AtlantisSyntaxTheme.preparingStackGap) {
            ProgressView()
            Text("Rendering \(AtlantisFormat.bytes(classification.byteCount))…")
                .font(Font(AtlantisSyntaxTheme.statsFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
    }

    /// Off-main, cached per `(mode, asciiVisible)` (perf contract rule 1/9a) —
    /// text and dump production happen entirely inside the detached task, so hex
    /// mode never builds the dump on the main thread, and never twice (B5-3).
    /// `builtCache` means toggling back to an already-streamed mode/pane combo
    /// is instant, served from the completed stream with no re-stream (B5-4).
    @MainActor
    private func streamIfNeeded() async {
        guard !isGated, kind != .empty, mode != .image, mode != .tree, !isClassifying else { stream = nil; return }
        let key = AtlantisBodyBuildKey(mode: mode, asciiVisible: asciiVisible)
        if let cached = builtCache[key] {
            stream = cached
            recomputeMatches()
            return
        }

        let mode = self.mode
        let ascii = self.asciiVisible
        let kind = self.kind
        let data = self.data
        let prettyText = classification.prettyText
        let rawText = classification.rawText
        let fallbackRawText = { String(decoding: data, as: UTF8.self) }
        let wordWrap = kind.wrapMode == .word

        let prepared: AtlantisBodyStreamPrepared = await Task.detached(priority: .userInitiated) {
            if mode == .hex {
                let dump = AtlantisHexDump.build(data, asciiVisible: ascii)
                let lineStarts = AtlantisSyntaxHighlighter.lineStarts(in: dump.text)
                let attributed = AtlantisBodyViewerView.buildHexAttributedString(text: dump.text, tokens: dump.tokens)
                let dividerOffsets = AtlantisBodyViewerView.hexDividerOffsets(asciiVisible: ascii)
                return AtlantisBodyStreamPrepared(text: dump.text, attributed: attributed, lineStarts: lineStarts,
                                                   hexDividerOffsets: dividerOffsets)
            }

            let text: String
            switch mode {
            case .pretty: text = prettyText ?? ""
            case .raw: text = rawText ?? fallbackRawText()
            case .text: text = rawText ?? ""
            case .hex, .image, .tree: text = ""
            }

            let lineStarts = AtlantisSyntaxHighlighter.lineStarts(in: text)
            let tokens: [AtlantisToken]
            switch mode {
            case .pretty:
                switch kind {
                case .json: tokens = AtlantisSyntaxHighlighter.jsonTokens(in: Array(text.utf16))
                case .xml, .html: tokens = AtlantisSyntaxHighlighter.xmlTokens(in: Array(text.utf16))
                default: tokens = []
                }
            default:
                tokens = []
            }
            let paragraph = AtlantisSyntaxTheme.paragraphStyle(wrapping: true, wordWrap: wordWrap)
            let attributed = AtlantisSyntaxHighlighter.attributedString(text: text, tokens: tokens,
                                                                         font: AtlantisSyntaxTheme.canvasFont,
                                                                         paragraphStyle: paragraph)
            return AtlantisBodyStreamPrepared(text: text, attributed: attributed, lineStarts: lineStarts, hexDividerOffsets: [])
        }.value
        guard !Task.isCancelled else { stream = nil; return }

        let newStream = AtlantisBodyStream(fullText: prepared.text, totalUTF16: prepared.attributed.length,
                                            hexDividerOffsets: prepared.hexDividerOffsets)
        stream = newStream
        recomputeMatches()

        let chunks = AtlantisBodyStream.makeChunks(attributed: prepared.attributed, lineStarts: prepared.lineStarts)
        for (index, chunk) in chunks.enumerated() {
            guard !Task.isCancelled else { stream = nil; return }
            newStream.append(chunk)
            recomputeMatches()
            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: AtlantisSyntaxTheme.streamYieldNanoseconds)
            }
        }
        guard !Task.isCancelled else { stream = nil; return }
        newStream.markComplete()
        builtCache[key] = newStream
        recomputeMatches()
    }

    // MARK: - JSON tree

    /// Parses `data` into an `AtlantisJSONValue` once per body (off-main) and
    /// (re)computes search/expansion state whenever tree mode is entered —
    /// cheap on an already-parsed tree, so re-running it on every mode
    /// switch back into `.tree` is fine (B5-3-equivalent: never re-parse).
    @MainActor
    private func buildTreeIfNeeded() async {
        guard mode == .tree, kind == .json, !isGated, !isClassifying else { return }
        if jsonTreeRoot == nil {
            let data = self.data
            let parsed = await Task.detached(priority: .userInitiated) {
                AtlantisJSONParser.parse(data)
            }.value
            guard !Task.isCancelled, let root = parsed else { return }
            jsonTreeRoot = root
            treeExpandedPaths = AtlantisJSONTree.defaultExpandedPaths(root: root)
        }
        recomputeTreeMatches()
    }

    private func rebuildTreeRows() {
        guard let root = jsonTreeRoot else { treeRows = []; return }
        treeRows = AtlantisJSONTree.rows(root: root, expanded: treeExpandedPaths)
    }

    private func toggleTreeNode(_ path: AtlantisJSONPath) {
        if treeExpandedPaths.contains(path) {
            treeExpandedPaths.remove(path)
        } else {
            treeExpandedPaths.insert(path)
        }
        rebuildTreeRows()
    }

    private func toggleExpandCollapseAll() {
        guard let root = jsonTreeRoot else { return }
        let all = AtlantisJSONTree.allExpandablePaths(root: root)
        treeExpandedPaths = treeExpandedPaths.count >= all.count ? [] : all
        rebuildTreeRows()
    }

    /// Recomputes tree search matches and auto-expands their ancestors
    /// (design: "on match it should auto-expand ancestors of any match so
    /// results are visible") — mirrors `recomputeMatches()`'s role for the
    /// text canvas.
    private func recomputeTreeMatches() {
        guard let root = jsonTreeRoot else { treeMatches = []; return }
        treeMatches = AtlantisJSONTree.matchingPaths(root: root, query: debouncedQuery)
        treeCurrentMatchIndex = 0
        if !treeMatches.isEmpty {
            var expanded = treeExpandedPaths
            for match in treeMatches {
                for ancestor in AtlantisJSONTree.ancestors(of: match) { expanded.insert(ancestor) }
            }
            treeExpandedPaths = expanded
        }
        rebuildTreeRows()
        scrollToken += 1
    }

    private func stepTree(_ delta: Int) {
        guard !treeMatches.isEmpty else { return }
        treeCurrentMatchIndex = (treeCurrentMatchIndex + delta + treeMatches.count) % treeMatches.count
        scrollToken += 1
    }

    private nonisolated static func buildHexAttributedString(text: String, tokens: [AtlantisToken]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: (text as NSString).length)
        result.addAttribute(.font, value: AtlantisSyntaxTheme.hexOffsetFont, range: full)
        result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.hexOffset, range: full)
        result.addAttribute(.paragraphStyle, value: AtlantisSyntaxTheme.noWrapParagraphStyle, range: full)
        for token in tokens {
            guard token.range.location >= 0, NSMaxRange(token.range) <= full.length else { continue }
            switch token.kind {
            case .hexOffset:
                result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.hexOffset, range: token.range)
                result.addAttribute(.font, value: AtlantisSyntaxTheme.hexOffsetFont, range: token.range)
            case .hexBytes:
                result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.hexBytes, range: token.range)
                result.addAttribute(.font, value: AtlantisSyntaxTheme.hexByteFont, range: token.range)
                result.addAttribute(.kern, value: AtlantisSyntaxTheme.hexByteKern, range: token.range)
            case .hexAscii:
                result.addAttribute(.foregroundColor, value: AtlantisSyntaxTheme.hexAscii, range: token.range)
                result.addAttribute(.font, value: AtlantisSyntaxTheme.hexAsciiFont, range: token.range)
            default:
                break
            }
        }
        return result
    }

    /// Divider x-offsets for the hex canvas — one before the bytes column,
    /// a second before the ASCII column when it's visible — measured from the
    /// same fixed-width fields `AtlantisHexDump.build` lays out (offset 8 +
    /// gap 2, bytes 48 kerned, gap 2, ascii). Monospaced fonts make every
    /// character's advance width uniform, so a representative run stands in
    /// for the real row (B-5, design §6.3). Relative to `canvasInset`.
    private nonisolated static func hexDividerOffsets(asciiVisible: Bool) -> [CGFloat] {
        func width(_ string: String, font: AtlantisSyntaxTheme.PlatformFont, kern: CGFloat = 0) -> CGFloat {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if kern != 0 { attributes[.kern] = kern }
            return (string as NSString).size(withAttributes: attributes).width
        }

        let offsetFieldWidth = width(String(repeating: "0", count: 8) + "  ", font: AtlantisSyntaxTheme.hexOffsetFont)
        let byteDivider = offsetFieldWidth
        guard asciiVisible else { return [byteDivider] }

        // 48 chars — same length as the `.hexBytes` token range `AtlantisHexDump.build`
        // emits (32 hex digits + 16 gap spaces); monospaced fonts give every
        // character in the field the same advance, so which character stands
        // in doesn't matter, only the count.
        let bytesFieldWidth = width(String(repeating: "0", count: 48), font: AtlantisSyntaxTheme.hexByteFont,
                                     kern: AtlantisSyntaxTheme.hexByteKern)
        let bytesGapWidth = width("  ", font: AtlantisSyntaxTheme.hexOffsetFont)
        let asciiDivider = byteDivider + bytesFieldWidth + bytesGapWidth
        return [byteDivider, asciiDivider]
    }

    // MARK: - Gate

    @ViewBuilder
    private var gateCard: some View {
        VStack(spacing: AtlantisSyntaxTheme.gateStackGap) {
            ZStack {
                RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.warnTileCornerRadius)
                    .fill(Color(AtlantisSyntaxTheme.warnTileFill))
                    .frame(width: AtlantisSyntaxTheme.warnTileSize, height: AtlantisSyntaxTheme.warnTileSize)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: AtlantisSyntaxTheme.warnGlyphSize, weight: .regular))
                    .foregroundColor(Color(AtlantisSyntaxTheme.warnGlyph))
            }

            Text("Large body")
                .font(Font(AtlantisSyntaxTheme.gateTitleFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))

            Text(AtlantisBodyGate.explanation(byteCount: classification.byteCount, badge: kind.badge))
                .font(Font(AtlantisSyntaxTheme.gateBodyFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: AtlantisSyntaxTheme.gateBodyMaxWidth)

            // A SwiftUI `Divider` ignores `.background` as a tint (B5-9) — a
            // fixed-height `Rectangle` with the pinned vertical margin instead.
            Rectangle()
                .fill(Color(AtlantisSyntaxTheme.divider))
                .frame(height: 0.5)
                .padding(.vertical, 2)

            VStack(spacing: AtlantisSyntaxTheme.gateButtonStackGap) {
                Button {
                    revealed = true
                } label: {
                    Text("Show body")
                        .font(Font(AtlantisSyntaxTheme.gateButtonFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelOnAccent))
                        .frame(maxWidth: .infinity, minHeight: AtlantisSyntaxTheme.gateButtonHeight)
                        .background(Color(AtlantisSyntaxTheme.accent))
                        .cornerRadius(AtlantisSyntaxTheme.gateButtonCornerRadius)
                }

                Button {
                    copy(rawModeText)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: AtlantisSyntaxTheme.gateSecondaryGlyphSize, weight: .regular))
                        Text("Copy instead")
                            .font(Font(AtlantisSyntaxTheme.gateButtonFontSecondary))
                    }
                    .foregroundColor(Color(AtlantisSyntaxTheme.accent))
                    .frame(maxWidth: .infinity, minHeight: AtlantisSyntaxTheme.gateButtonHeight)
                    .background(Color(AtlantisSyntaxTheme.accentFill))
                    .cornerRadius(AtlantisSyntaxTheme.gateButtonCornerRadius)
                }

                Text(AtlantisBodyGate.footnote(limit: AtlantisViewerSettings.autoRenderLimitBytes))
                    .font(Font(AtlantisSyntaxTheme.footnoteFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelQuaternary))
                    .multilineTextAlignment(.center)
                    .padding(.top, AtlantisSyntaxTheme.gateFootnoteTopPadding)
            }
        }
        .padding(.vertical, AtlantisSyntaxTheme.gateCardPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.gateCardPaddingHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
    }
}

private func atlantisImageSize(_ data: Data) -> CGSize {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return UIImage(data: data)?.size ?? .zero
    #elseif os(macOS)
    return NSImage(data: data)?.size ?? .zero
    #else
    return .zero
    #endif
}

// MARK: - Meta card

private struct AtlantisBodyMetaCard: View {
    let kind: AtlantisBodyClassifiedKind
    let contentType: String?
    let statsLine: String

    private var badgeColors: (fg: AtlantisSyntaxTheme.PlatformColor, fill: AtlantisSyntaxTheme.PlatformColor) {
        switch kind {
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

    var body: some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.metaCardRowGap) {
            HStack(spacing: AtlantisSyntaxTheme.metaBadgeGap) {
                Text(kind.badge)
                    .font(Font(AtlantisSyntaxTheme.badgeFont))
                    .tracking(0.6)
                    .foregroundColor(Color(badgeColors.fg))
                    .padding(.vertical, AtlantisSyntaxTheme.badgePaddingVertical)
                    .padding(.horizontal, AtlantisSyntaxTheme.badgePaddingHorizontal)
                    .background(Color(badgeColors.fill))
                    .cornerRadius(AtlantisSyntaxTheme.badgeCornerRadius)

                Text(contentType?.isEmpty == false ? contentType! : "—")
                    .font(Font(AtlantisSyntaxTheme.contentTypeFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            Text(statsLine)
                .font(Font(AtlantisSyntaxTheme.statsFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
        }
        .padding(.vertical, AtlantisSyntaxTheme.metaCardPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.metaCardPaddingHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.cardCornerRadius)
    }
}

// MARK: - Segmented mode picker

private struct AtlantisBodySegmentedPicker: View {
    @Binding var mode: AtlantisBodyMode
    let options: [AtlantisBodyMode]
    let disabled: Set<AtlantisBodyMode>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == mode
                let isDisabled = disabled.contains(option)
                Button {
                    guard !isDisabled else { return }
                    mode = option
                } label: {
                    Text(option.label)
                        .font(Font(isSelected ? AtlantisSyntaxTheme.segmentFontSelected : AtlantisSyntaxTheme.segmentFont))
                        .foregroundColor(Color(isDisabled ? AtlantisSyntaxTheme.segmentLabelDisabled :
                                                (isSelected ? AtlantisSyntaxTheme.segmentSelectedLabel : AtlantisSyntaxTheme.segmentLabel)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AtlantisSyntaxTheme.segmentPaddingVertical)
                        .background(
                            isSelected ?
                                RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.segmentCornerRadius)
                                    .fill(Color(AtlantisSyntaxTheme.segmentSelectedFill))
                                    // Dark-mode alpha is 0 on this token, so the
                                    // shadow is a no-op there without a
                                    // color-scheme branch (design §5.1, B5-8).
                                    .shadow(color: Color(AtlantisSyntaxTheme.segmentSelectedShadowColor),
                                            radius: AtlantisSyntaxTheme.segmentSelectedShadowRadius,
                                            x: 0, y: AtlantisSyntaxTheme.segmentSelectedShadowY)
                                : nil
                        )
                }
                .disabled(isDisabled)
            }
        }
        .padding(AtlantisSyntaxTheme.segmentTrackPadding)
        .background(Color(AtlantisSyntaxTheme.controlTrackFill))
        .cornerRadius(AtlantisSyntaxTheme.segmentTrackCornerRadius)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Icon chip

private struct AtlantisBodyIconChip<Glyph: View>: View {
    let isActive: Bool
    let isCopied: Bool
    let help: String
    let accessibilityLabel: String
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isCopied {
                    Text("Copied")
                        .font(Font(AtlantisSyntaxTheme.footnoteFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.accent))
                } else {
                    glyph()
                        .foregroundColor(Color(isActive ? AtlantisSyntaxTheme.accent : AtlantisSyntaxTheme.chipGlyphInactive))
                }
            }
            .frame(width: AtlantisSyntaxTheme.chipSize, height: AtlantisSyntaxTheme.chipSize)
            .background(Color(isActive ? AtlantisSyntaxTheme.accentFill : AtlantisSyntaxTheme.neutralFill))
            .cornerRadius(AtlantisSyntaxTheme.chipCornerRadius)
            // `.contentShape` clips to the button's own bounds — it cannot
            // extend the tap area beyond the 34×34 visual, so the frame itself
            // is padded to the 44×44 hit target with the visual centered
            // inside it (B5-10).
            .frame(width: AtlantisSyntaxTheme.chipHitTarget, height: AtlantisSyntaxTheme.chipHitTarget)
            .contentShape(Rectangle())
        }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Search row

private struct AtlantisBodySearchRow: View {
    @Binding var query: String
    let matchCount: Int
    let currentMatchIndex: Int
    let onPrev: () -> Void
    let onNext: () -> Void

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { !trimmed.isEmpty }

    var body: some View {
        HStack(spacing: AtlantisSyntaxTheme.searchRowGap) {
            HStack(spacing: AtlantisSyntaxTheme.searchPillInnerGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AtlantisSyntaxTheme.searchGlyphSize, weight: .regular))
                    .foregroundColor(Color(AtlantisSyntaxTheme.searchGlyph))
                TextField("Search", text: $query)
                    .font(Font(AtlantisSyntaxTheme.searchQueryFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.searchQueryText))
                    .textFieldStyle(.plain)
                    .tint(Color(AtlantisSyntaxTheme.searchCaret))
            }
            .padding(.horizontal, AtlantisSyntaxTheme.searchPillPaddingHorizontal)
            .frame(height: AtlantisSyntaxTheme.searchPillHeight)
            .background(Color(AtlantisSyntaxTheme.controlTrackFill))
            .cornerRadius(AtlantisSyntaxTheme.searchPillCornerRadius)
            .frame(maxWidth: .infinity)

            if hasQuery {
                if matchCount == 0 {
                    Text("No matches")
                        .font(Font(AtlantisSyntaxTheme.statsFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.counterText))
                } else {
                    Text("\(currentMatchIndex + 1)/\(matchCount)")
                        .font(Font(AtlantisSyntaxTheme.counterFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.counterText))
                        .monospacedDigit()
                        .frame(minWidth: AtlantisSyntaxTheme.counterMinWidth, alignment: .trailing)
                }
            }

            HStack(spacing: AtlantisSyntaxTheme.chevronGap) {
                chevron(systemName: "chevron.up", action: onPrev)
                chevron(systemName: "chevron.down", action: onNext)
            }
        }
    }

    private func chevron(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AtlantisSyntaxTheme.chevronGlyphSize, weight: .bold))
                .foregroundColor(Color(matchCount == 0 ? AtlantisSyntaxTheme.labelDisabled : AtlantisSyntaxTheme.chevronActive))
                .frame(width: AtlantisSyntaxTheme.chevronButtonWidth, height: AtlantisSyntaxTheme.chevronButtonHeight)
        }
        .disabled(matchCount == 0)
        #if os(macOS)
        .keyboardShortcut("g",
                           modifiers: systemName == "chevron.down" ? [.command] : [.command, .shift])
        #endif
    }
}

// MARK: - UTF-8 banner

private struct AtlantisBodyUTF8Banner: View {
    let invalidByteCount: Int
    let firstInvalidOffset: Int

    var body: some View {
        HStack(alignment: .top, spacing: AtlantisSyntaxTheme.bannerGap) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: AtlantisSyntaxTheme.bannerGlyphSize, weight: .bold))
                .foregroundColor(Color(AtlantisSyntaxTheme.warnGlyph))
                .padding(.top, 1)
                .fixedSize()
            Text(AtlantisBodyBanner.utf8Text(invalidByteCount: invalidByteCount, firstInvalidOffset: firstInvalidOffset))
                .font(Font(AtlantisSyntaxTheme.bannerFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.bannerText))
        }
        .padding(.vertical, AtlantisSyntaxTheme.bannerPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.bannerPaddingHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.bannerFill))
        .cornerRadius(AtlantisSyntaxTheme.bannerCornerRadius)
    }
}

// MARK: - Progressive-render banner

/// Shown between the search row and the canvas card while a stream is
/// mid-flight (docs/plan-progressive-body-render.md Part 3) — mirrors
/// `AtlantisBodyUTF8Banner`'s styling with a small spinner in place of the
/// exclamation glyph. `loadedUTF16`/`totalUTF16` are UTF-16 code-unit counts,
/// not bytes — close enough to the payload's byte count for mostly-ASCII
/// bodies (JSON/XML/text) to read as a meaningful progress figure.
private struct AtlantisBodyStreamBanner: View {
    let loadedUTF16: Int
    let totalUTF16: Int

    var body: some View {
        HStack(alignment: .center, spacing: AtlantisSyntaxTheme.bannerGap) {
            ProgressView()
                .controlSize(.small)
            Text("Loading — \(AtlantisFormat.bytes(loadedUTF16)) of \(AtlantisFormat.bytes(totalUTF16)) · search covers loaded text only")
                .font(Font(AtlantisSyntaxTheme.bannerFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.bannerText))
        }
        .padding(.vertical, AtlantisSyntaxTheme.bannerPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.bannerPaddingHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.bannerFill))
        .cornerRadius(AtlantisSyntaxTheme.bannerCornerRadius)
    }
}

// MARK: - Empty state

private struct AtlantisBodyEmptyStateView: View {
    let method: String
    let side: AtlantisBodySide
    let statusCode: Int?

    var body: some View {
        VStack(spacing: AtlantisSyntaxTheme.emptyStackGap) {
            Image(systemName: "doc")
                .font(.system(size: AtlantisSyntaxTheme.emptyGlyphSize, weight: .light))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelDisabled))
            Text("No body")
                .font(Font(AtlantisSyntaxTheme.gateTitleFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelHeading))
            Text(AtlantisBodyEmptyHint.byteLine)
                .font(Font(AtlantisSyntaxTheme.emptyBytesFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            Text(AtlantisBodyEmptyHint.text(method: method, side: side, statusCode: statusCode))
                .font(Font(AtlantisSyntaxTheme.hintFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelQuaternary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: AtlantisSyntaxTheme.emptyHintMaxWidth)
        }
        .padding(.horizontal, AtlantisSyntaxTheme.emptyPaddingHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image mode

private struct AtlantisBodyImageView: View {
    let data: Data
    @Binding var scale: CGFloat
    /// `scale` at the start of the current pinch gesture — `MagnificationGesture`'s
    /// `value` is relative to the gesture's own start, not the running scale, so
    /// without this a pinch released at 3× and restarted snaps back to ~1× (N-3).
    @State private var baseScale: CGFloat = 1

    var body: some View {
        ZStack {
            AtlantisCheckerboard()
            platformImage
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(baseScale * value, AtlantisSyntaxTheme.imageZoomMin), AtlantisSyntaxTheme.imageZoomMax)
                        }
                        .onEnded { _ in
                            baseScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    scale = 1
                    baseScale = 1
                }
        }
        .clipped()
    }

    @ViewBuilder
    private var platformImage: some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFit()
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage).resizable().scaledToFit()
        }
        #endif
    }
}

private struct AtlantisCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    let isDark = (row + col) % 2 == 0
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(isDark ? Color(AtlantisSyntaxTheme.gutterFill) : Color(AtlantisSyntaxTheme.cardFill)))
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}
#endif

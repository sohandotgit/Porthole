//
//  AtlantisSyntaxTheme.swift
//  atlantis
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Token kinds emitted by `AtlantisSyntaxHighlighter`.
enum AtlantisTokenKind: Equatable {
    case key
    case string
    case number
    case literal
    case punctuation
    case plain
    case tagName
    case attrName
    case attrValue
    case comment
    case hexOffset
    case hexBytes
    case hexAscii
}

/// Dynamic light/dark colors, fonts, and paragraph styles for the body viewer's
/// syntax-highlighted canvas. Every color literal in the body path lives here
/// (design/body-viewer-tokens.md, typed verbatim).
enum AtlantisSyntaxTheme {

    #if canImport(UIKit)
    typealias PlatformColor = UIColor
    #elseif canImport(AppKit)
    typealias PlatformColor = NSColor
    #endif

    // MARK: - Color construction

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> PlatformColor {
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        #if canImport(UIKit)
        return PlatformColor(red: r, green: g, blue: b, alpha: alpha)
        #elseif canImport(AppKit)
        return PlatformColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        #endif
    }

    private static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #elseif canImport(AppKit)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }
        #endif
    }

    private static func pair(_ lightHex: UInt32, _ darkHex: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> PlatformColor {
        dynamic(light: hex(lightHex, alpha: lightAlpha), dark: hex(darkHex, alpha: darkAlpha))
    }

    // MARK: - Syntax tokens (canvas text) — tokens.md §1

    static let syntaxKey = pair(0x9B2393, 0xFF7AB2)
    static let syntaxString = pair(0xC41A16, 0xFF8170)
    static let syntaxNumber = pair(0x1C00CF, 0xD9C97C)
    static let syntaxLiteral = pair(0xAA0D91, 0xFF7AB2)
    static let syntaxPunctuation = pair(0x6E6E73, 0x98989F)
    static let syntaxPlain = pair(0x1C1C1E, 0xF2F2F7)
    static let syntaxTagName = pair(0x9B2393, 0xFF7AB2)
    static let syntaxAttrName = pair(0x804000, 0xE8A33D)
    static let syntaxAttrValue = pair(0xC41A16, 0xFF8170)
    static let syntaxComment = pair(0x5D6C79, 0x7E8C99)
    static let hexOffset = pair(0x5A5A5F, 0x5A5A5F)
    static let hexBytes = pair(0x1C1C1E, 0xEBEBF5)
    static let hexAscii = pair(0x2E7D53, 0x7DD3A0)

    // MARK: - JSON tree view (design_handoff_tree_view §Design Tokens)

    /// Vertical ancestor-nesting guide lines — distinct from `syntaxPunctuation`
    /// (used for the chevron and the colon), matching the design's separate
    /// "chevron / guide line" token pair.
    static let treeGuideLine = pair(0xD1D1D6, 0x3A3A3C)
    static let treeCollapsedPreview = pair(0x8E8E93, 0x98989F)

    // MARK: - Search highlight — tokens.md §2

    static let matchBackground = pair(0xFFD60A, 0xFFD60A, lightAlpha: 0.42, darkAlpha: 0.28)
    static let currentMatchBackground = pair(0xFFCC00, 0xFFD60A)
    static let currentMatchRing = pair(0xB25000, 0xFFF3B0)
    static let currentMatchForeground = pair(0x1C1C1E, 0x1C1C1E)
    /// Pinned in the design's script alongside `currentMatchMarker`; the mock markup
    /// never binds either. v2 §8.3(a) mandates drawing the row tint — a deliberate
    /// amendment beyond the mock (B7-1) — while `currentMatchMarker` stays reserved.
    static let currentRowTint = pair(0xFFD60A, 0xFFD60A, lightAlpha: 0.14, darkAlpha: 0.10)
    static let currentMatchMarker = pair(0xFFCC00, 0xFFD60A)

    static let currentMatchRingWidth: CGFloat = 1.5
    static let currentMatchRingInset: CGFloat = 0.75
    static let matchCornerRadius: CGFloat = 3

    // MARK: - Surfaces, gutter, chrome — tokens.md §3

    static let pageFill = pair(0xF2F2F7, 0x000000)
    static let cardFill = pair(0xFFFFFF, 0x1C1C1E)
    static let gutterFill = pair(0xFBFBFD, 0x141416)
    static let gutterDivider = pair(0xE5E5EA, 0x2C2C2E)
    static let gutterText = pair(0xB0B0B6, 0x5A5A5F)
    static let gutterTextCurrent = pair(0x007AFF, 0x0A84FF)
    static let accent = pair(0x007AFF, 0x0A84FF)
    static let accentFill = pair(0x007AFF, 0x0A84FF, lightAlpha: 0.12, darkAlpha: 0.22)
    static let neutralFill = pair(0x767680, 0x767680, lightAlpha: 0.10, darkAlpha: 0.24)
    static let controlTrackFill = pair(0x767680, 0x767680, lightAlpha: 0.12, darkAlpha: 0.24)
    static let segmentSelectedFill = pair(0xFFFFFF, 0x636366)
    static let segmentSelectedLabel = pair(0x000000, 0xFFFFFF)
    static let segmentLabel = pair(0x3C3C43, 0xEBEBF5)
    static let segmentLabelDisabled = pair(0xAEAEB2, 0x636366)
    static let chipGlyphInactive = pair(0x3C3C43, 0xEBEBF5)
    static let divider = pair(0xE5E5EA, 0x38383A)
    static let labelPrimary = pair(0x000000, 0xFFFFFF)
    static let labelHeading = pair(0x3C3C43, 0xEBEBF5)
    static let labelSecondary = pair(0x6C6C70, 0x98989F)
    static let labelTertiary = pair(0x8E8E93, 0x8E8E93)
    static let labelQuaternary = pair(0xAEAEB2, 0x8E8E93)
    static let labelDisabled = pair(0xC7C7CC, 0x48484A)
    static let searchCaret = pair(0x007AFF, 0x0A84FF)
    static let searchGlyph = pair(0x8E8E93, 0x98989F)
    static let searchQueryText = pair(0x000000, 0xFFFFFF)
    static let counterText = pair(0x6C6C70, 0x98989F)
    static let labelOnAccent = pair(0xFFFFFF, 0xFFFFFF)
    static let chevronActive = accent
    static let segmentSelectedShadowColor = pair(0x000000, 0x000000, lightAlpha: 0.12, darkAlpha: 0)

    // MARK: - Format-badge tints — tokens.md §4

    static let badgeJSONForeground = pair(0x0B63CE, 0x6FB6FF)
    static let badgeJSONFill = pair(0x007AFF, 0x0A84FF, lightAlpha: 0.12, darkAlpha: 0.22)
    static let badgeBinaryForeground = pair(0x7A1FA2, 0xD4B7FF)
    static let badgeBinaryFill = pair(0xAF5AE2, 0xBF5AF2, lightAlpha: 0.12, darkAlpha: 0.22)
    static let badgeXMLForeground = badgeBinaryForeground
    static let badgeXMLFill = badgeBinaryFill
    static let badgeHTMLForeground = badgeBinaryForeground
    static let badgeHTMLFill = badgeBinaryFill
    static let badgeFormForeground = pair(0x0B6E6E, 0x5FD8E0)
    static let badgeFormFill = pair(0x30B0C7, 0x64D2FF, lightAlpha: 0.12, darkAlpha: 0.22)
    static let badgeImageForeground = pair(0x1D7A3D, 0x7DD3A0)
    static let badgeImageFill = pair(0x34C759, 0x30D158, lightAlpha: 0.12, darkAlpha: 0.22)
    static let badgeTextForeground = pair(0x5A5A5F, 0xC7C7CC)
    static let badgeTextFill = pair(0x767680, 0x767680, lightAlpha: 0.12, darkAlpha: 0.24)

    // MARK: - Warning surfaces — tokens.md §5

    static let warnTileFill = pair(0xFF9500, 0xFF9F0A, lightAlpha: 0.14, darkAlpha: 0.18)
    static let warnGlyph = pair(0xC86000, 0xFFB340)
    static let bannerFill = pair(0xFF9500, 0xFF9F0A, lightAlpha: 0.12, darkAlpha: 0.14)
    static let bannerText = pair(0x8A4B00, 0xFFD9A0)

    /// Exhaustive over `AtlantisTokenKind`.
    static func color(for kind: AtlantisTokenKind) -> PlatformColor {
        switch kind {
        case .key: return syntaxKey
        case .string: return syntaxString
        case .number: return syntaxNumber
        case .literal: return syntaxLiteral
        case .punctuation: return syntaxPunctuation
        case .plain: return syntaxPlain
        case .tagName: return syntaxTagName
        case .attrName: return syntaxAttrName
        case .attrValue: return syntaxAttrValue
        case .comment: return syntaxComment
        case .hexOffset: return hexOffset
        case .hexBytes: return hexBytes
        case .hexAscii: return hexAscii
        }
    }

    // MARK: - Fonts — tokens.md §7

    static let maximumPointSize: CGFloat = 22

    #if canImport(UIKit)
    private static let bodyMetrics = UIFontMetrics(forTextStyle: .body)
    #endif

    private static func monospaced(_ size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
        #if canImport(UIKit)
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        return bodyMetrics.scaledFont(for: base, maximumPointSize: maximumPointSize)
        #elseif canImport(AppKit)
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        #endif
    }

    private static func system(_ size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return bodyMetrics.scaledFont(for: base, maximumPointSize: maximumPointSize)
        #elseif canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    #if canImport(UIKit)
    typealias PlatformFont = UIFont
    typealias PlatformFontWeight = UIFont.Weight
    #elseif canImport(AppKit)
    typealias PlatformFont = NSFont
    typealias PlatformFontWeight = NSFont.Weight
    #endif

    // Computed, not cached: `UIFontMetrics.scaledFont` bakes in the content size
    // category at call time, so these must be re-resolved on every access rather
    // than frozen once in a `static let` — otherwise a Dynamic Type change after
    // first access never takes effect (B4-5). macOS applies no metrics scaling
    // (`monospaced`/`system` ignore the category there), so `maximumPointSize` is a
    // deliberate no-op on that platform.
    static var canvasFont: PlatformFont { monospaced(13, weight: .regular) }
    static var gutterFont: PlatformFont { monospaced(12, weight: .regular) }
    static var gutterFontCurrent: PlatformFont { monospaced(12, weight: .semibold) }
    static var hexOffsetFont: PlatformFont { monospaced(11, weight: .regular) }
    static var hexByteFont: PlatformFont { monospaced(11.5, weight: .regular) }
    static var hexAsciiFont: PlatformFont { monospaced(11.5, weight: .regular) }
    static var badgeFont: PlatformFont { monospaced(11, weight: .semibold) }
    static var contentTypeFont: PlatformFont { monospaced(13, weight: .regular) }
    static var statsFont: PlatformFont { system(13, weight: .regular) }
    static var segmentFont: PlatformFont { system(13, weight: .regular) }
    static var segmentFontSelected: PlatformFont { system(13, weight: .semibold) }
    static var chipGlyphFont: PlatformFont { monospaced(12, weight: .semibold) }
    static var chipGlyphFontSmall: PlatformFont { monospaced(11, weight: .semibold) }
    static var searchQueryFont: PlatformFont { monospaced(15, weight: .regular) }
    static var counterFont: PlatformFont { monospaced(13, weight: .medium) }
    static var bannerFont: PlatformFont { system(13, weight: .regular) }
    static var gateTitleFont: PlatformFont { system(20, weight: .semibold) }
    static var gateBodyFont: PlatformFont { system(15, weight: .regular) }
    static var gateButtonFont: PlatformFont { system(17, weight: .semibold) }
    static var gateButtonFontSecondary: PlatformFont { system(17, weight: .medium) }
    static var footnoteFont: PlatformFont { system(12, weight: .regular) }
    static var hintFont: PlatformFont { system(13, weight: .regular) }
    static var emptyBytesFont: PlatformFont { monospaced(15, weight: .regular) }
    static var navTitleFont: PlatformFont { system(17, weight: .semibold) }
    static var navButtonFont: PlatformFont { system(17, weight: .regular) }
    static var treeKeyFont: PlatformFont { monospaced(13, weight: .semibold) }
    static var treeValueFont: PlatformFont { monospaced(13, weight: .regular) }

    // MARK: - Metrics used by the theme (line box / hex kern)

    static let canvasLineHeight: CGFloat = 22
    static let hexByteKern: CGFloat = 0.3

    // MARK: - Paragraph styles

    /// Wrapping canvas paragraph style (`.byCharWrapping` / `.byWordWrapping` per kind).
    static func paragraphStyle(wrapping: Bool, wordWrap: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = canvasLineHeight
        style.maximumLineHeight = canvasLineHeight
        if wrapping {
            style.lineBreakMode = wordWrap ? .byWordWrapping : .byCharWrapping
        } else {
            style.lineBreakMode = .byClipping
        }
        return style
    }

    static let wrapParagraphStyleCharacter = paragraphStyle(wrapping: true, wordWrap: false)
    static let wrapParagraphStyleWord = paragraphStyle(wrapping: true, wordWrap: true)
    static let noWrapParagraphStyle = paragraphStyle(wrapping: false, wordWrap: false)

    // MARK: - Metrics — tokens.md §8

    static let cardCornerRadius: CGFloat = 12
    static let contentColumnPaddingTop: CGFloat = 14
    static let contentColumnPaddingHorizontal: CGFloat = 16
    static let gateContentBottomPadding: CGFloat = 14
    static let cardGap: CGFloat = 14
    static let cardGapHex: CGFloat = 12
    static let metaCardPaddingVertical: CGFloat = 12
    static let metaCardPaddingHorizontal: CGFloat = 14
    static let metaCardRowGap: CGFloat = 7
    static let metaBadgeGap: CGFloat = 9
    static let badgeCornerRadius: CGFloat = 6
    static let badgePaddingVertical: CGFloat = 5
    static let badgePaddingHorizontal: CGFloat = 8
    static let controlStripGap: CGFloat = 10
    static let segmentTrackCornerRadius: CGFloat = 9
    static let segmentTrackPadding: CGFloat = 2
    static let segmentCornerRadius: CGFloat = 7
    static let segmentPaddingVertical: CGFloat = 7
    static let chipSize: CGFloat = 34
    static let chipCornerRadius: CGFloat = 8
    static let chipGap: CGFloat = 4
    static let chipHitTarget: CGFloat = 44
    static let searchRowGap: CGFloat = 8
    static let searchPillHeight: CGFloat = 36
    static let searchPillCornerRadius: CGFloat = 10
    static let searchPillPaddingHorizontal: CGFloat = 9
    static let searchPillInnerGap: CGFloat = 6
    static let searchGlyphSize: CGFloat = 14
    static let counterMinWidth: CGFloat = 38
    static let chevronButtonWidth: CGFloat = 30
    static let chevronButtonHeight: CGFloat = 32
    static let chevronGlyphSize: CGFloat = 13
    static let chevronGap: CGFloat = 2
    static let bannerCornerRadius: CGFloat = 10
    static let bannerPaddingVertical: CGFloat = 10
    static let bannerPaddingHorizontal: CGFloat = 12
    static let bannerGap: CGFloat = 9
    static let bannerGlyphSize: CGFloat = 16
    static let warnTileSize: CGFloat = 56
    static let warnTileCornerRadius: CGFloat = 16
    static let warnGlyphSize: CGFloat = 30
    static let gateCardPaddingVertical: CGFloat = 32
    static let gateCardPaddingHorizontal: CGFloat = 28
    static let gateStackGap: CGFloat = 14
    static let gateBodyMaxWidth: CGFloat = 250
    static let gateButtonHeight: CGFloat = 48
    static let gateButtonCornerRadius: CGFloat = 12
    static let gateButtonStackGap: CGFloat = 9
    static let gateSecondaryGlyphSize: CGFloat = 17
    static let gateFootnoteTopPadding: CGFloat = 2
    static let emptyStackGap: CGFloat = 12
    static let emptyPaddingHorizontal: CGFloat = 40
    static let emptyGlyphSize: CGFloat = 52
    static let emptyHintMaxWidth: CGFloat = 230
    static let wrapGlyphSize: CGFloat = 18
    static let copyGlyphSize: CGFloat = 17
    static let navEllipsisSize: CGFloat = 24

    // MARK: - JSON tree view metrics (design_handoff_tree_view §Layout/§Spacing scale)

    /// Indent step per nesting level; a row at `depth` is padded
    /// `depth * treeIndentStep + treeIndentBase`, and its ancestor guide lines
    /// sit at `level * treeIndentStep + treeGuideOffset` for each `level` in
    /// `0..<depth`.
    static let treeIndentStep: CGFloat = 18
    static let treeIndentBase: CGFloat = 6
    static let treeGuideOffset: CGFloat = 13
    static let treeGuideWidth: CGFloat = 1
    static let treeRowPaddingVertical: CGFloat = 4
    static let treeRowPaddingHorizontal: CGFloat = 8
    static let treeRowGap: CGFloat = 2
    static let treeRowLineHeight: CGFloat = 20
    static let treeChevronHitSize: CGFloat = 14
    static let treeChevronGlyphSize: CGFloat = 8
    static let treeCanvasPaddingVertical: CGFloat = 8
    static let treeCanvasPaddingHorizontal: CGFloat = 4
    static let treeToolbarGlyphSize: CGFloat = 15

    // MARK: - Canvas / gutter / hex measurements — tokens.md §8/§9

    static let canvasInset: CGFloat = 12
    static let canvasOverscrollBottom: CGFloat = 16
    static let lineFragmentPadding: CGFloat = 0
    static let gutterWidthFloor: CGFloat = 44
    static let gutterWidthPadding: CGFloat = 22
    static let gutterPaddingLeading: CGFloat = 12
    static let gutterPaddingTrailing: CGFloat = 10
    static let gutterPaddingVertical: CGFloat = 12
    static let gutterDividerWidth: CGFloat = 0.5
    static let hexOffsetPaddingLeading: CGFloat = 12
    static let hexOffsetPaddingTrailing: CGFloat = 10
    static let hexColumnDividerWidth: CGFloat = 0.5
    static let hexColumnMarginGap: CGFloat = 10
    static let hexColumnPaddingGap: CGFloat = 10
    static let scrollToMatchFraction: CGFloat = 1.0 / 3.0
    static let segmentSelectedShadowRadius: CGFloat = 3
    static let segmentSelectedShadowY: CGFloat = 1

    // MARK: - Preview card — tokens.md §8

    static let previewMaxLines: Int = 14
    static let previewByteBudget: Int = 2_048
    static let previewFadeHeight: CGFloat = 24
    static let previewThumbnailSize: CGFloat = 64
    static let previewChevronGlyphSize: CGFloat = 13

    // MARK: - Behavioral constants — tokens.md §9

    static let searchDebounceNanoseconds: UInt64 = 150_000_000
    static let copyConfirmationDuration: Double = 1.2
    static let imageZoomMin: CGFloat = 1
    static let imageZoomMax: CGFloat = 6

    // MARK: - Progressive body streaming — docs/plan-progressive-body-render.md

    /// First chunk is capped smaller than the steady-state chunk size so
    /// something is on screen in one frame.
    static let streamFirstChunkMaxLines = 400
    static let streamChunkMaxLines = 2_000
    static let streamChunkMaxUTF16 = 64 * 1_024
    /// One-runloop-turn gap between chunk appends so the first chunk paints
    /// and the UI stays responsive.
    static let streamYieldNanoseconds: UInt64 = 1_000_000
    static let preparingStackGap: CGFloat = 10
    static let preparingGlyphScale: CGFloat = 1.2

    // MARK: - Request Overview: band surfaces — request-overview-tokens.md §1

    static let bandFillGreen = pair(0xEAF7EC, 0x10240F)
    static let bandFillRed = pair(0xFFEDEB, 0x2A0F0D)
    static let bandFillOrange = pair(0xFFF4E5, 0x2A1B05)
    static let bandFillPurple = pair(0xF6EDFF, 0x1E1030)

    static let bandHairlineGreen = pair(0x34C759, 0x30D158, lightAlpha: 0.35, darkAlpha: 0.32)
    static let bandHairlineRed = pair(0xFF3B30, 0xFF453A, lightAlpha: 0.30, darkAlpha: 0.32)
    static let bandHairlineOrange = pair(0xFF9500, 0xFF9F0A, lightAlpha: 0.35, darkAlpha: 0.32)
    static let bandHairlinePurple = pair(0xAF52DE, 0xBF5AF2, lightAlpha: 0.35, darkAlpha: 0.32)

    static let bandHairlineWidth: CGFloat = 0.5

    // MARK: - Request Overview: band content — request-overview-tokens.md §2

    static let chipFillGreen = pair(0x34C759, 0x30D158, lightAlpha: 0.18, darkAlpha: 0.20)
    static let chipFillRed = pair(0xFF3B30, 0xFF453A, lightAlpha: 0.14, darkAlpha: 0.20)
    static let chipFillOrange = pair(0xFF9500, 0xFF9F0A, lightAlpha: 0.18, darkAlpha: 0.22)
    static let chipFillPurple = pair(0xAF52DE, 0xBF5AF2, lightAlpha: 0.16, darkAlpha: 0.22)

    static let statusDeepGreen = pair(0x12592A, 0x4FE070)
    static let statusDeepRed = pair(0xA81C14, 0xFF6B5E)
    static let statusDeepOrange = pair(0x8A4300, 0xFFB340)
    static let statusMidGreen = pair(0x1A6B33, 0x7BE495)
    static let statusMidRed = pair(0xC9241B, 0xFF9A90)
    static let statusMidOrange = pair(0xB25000, 0xFFC46B)
    static let statusMidPurple = pair(0x7A1FA2, 0xD8A0F5)

    static let hostLabelGreen = pair(0x3C6B45, 0x8FBF9C)
    static let hostLabelRed = pair(0x8A5C58, 0xC9A09B)
    static let hostLabelOrange = pair(0x8A6A45, 0xD9BE93)
    static let hostLabelPurple = pair(0x6E3E8C, 0xC9A6E0)

    static let affordanceFillGreen = pair(0x34C759, 0x30D158, lightAlpha: 0.16, darkAlpha: 0.20)
    static let affordanceFillRed = pair(0xFF3B30, 0xFF453A, lightAlpha: 0.12, darkAlpha: 0.20)
    static let affordanceFillOrange = pair(0xFF9500, 0xFF9F0A, lightAlpha: 0.18, darkAlpha: 0.22)
    static let affordanceFillPurple = pair(0xAF52DE, 0xBF5AF2, lightAlpha: 0.16, darkAlpha: 0.22)

    /// Exhaustive over `AtlantisStatusFamily` — a seventh family cannot be added
    /// without visiting every token group (request-overview-tokens.md §0).
    static func bandFill(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return bandFillGreen
        case .clientError, .pending: return bandFillOrange
        case .serverError, .transportError: return bandFillRed
        case .websocket: return bandFillPurple
        }
    }

    static func bandHairline(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return bandHairlineGreen
        case .clientError, .pending: return bandHairlineOrange
        case .serverError, .transportError: return bandHairlineRed
        case .websocket: return bandHairlinePurple
        }
    }

    static func chipFill(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return chipFillGreen
        case .clientError, .pending: return chipFillOrange
        case .serverError, .transportError: return chipFillRed
        case .websocket: return chipFillPurple
        }
    }

    static func statusDeep(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return statusDeepGreen
        case .clientError, .pending: return statusDeepOrange
        case .serverError, .transportError: return statusDeepRed
        case .websocket: return labelPrimary
        }
    }

    static func statusMid(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return statusMidGreen
        case .clientError, .pending: return statusMidOrange
        case .serverError, .transportError: return statusMidRed
        case .websocket: return statusMidPurple
        }
    }

    static func hostLabel(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return hostLabelGreen
        case .clientError, .pending: return hostLabelOrange
        case .serverError, .transportError: return hostLabelRed
        case .websocket: return hostLabelPurple
        }
    }

    static func affordanceFill(_ family: AtlantisStatusFamily) -> PlatformColor {
        switch family {
        case .success: return affordanceFillGreen
        case .clientError, .pending: return affordanceFillOrange
        case .serverError, .transportError: return affordanceFillRed
        case .websocket: return affordanceFillPurple
        }
    }

    static func affordanceGlyph(_ family: AtlantisStatusFamily) -> PlatformColor {
        statusMid(family)
    }

    // MARK: - Request Overview: path card / error card — request-overview-tokens.md §3

    static let pathCardFill = pair(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.72, darkAlpha: 0.07)
    static let errorCardFill = pair(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.80, darkAlpha: 0.07)
    static let errorHeadline = pair(0xA81C14, 0xFF6B5E)
    static let errorCode = pair(0x8A231D, 0xFF9A90)
    static let errorButtonFill = pair(0xFF3B30, 0xFF453A, lightAlpha: 0.12, darkAlpha: 0.20)
    static let errorButtonLabel = pair(0xC9241B, 0xFF9A90)

    // MARK: - Request Overview: cards, rows, tiles, skeleton — request-overview-tokens.md §4

    static let chevronPassive = pair(0xC7C7CC, 0x48484A)
    static let chevronDimmed = pair(0xE5E5EA, 0x2C2C2E)
    static let rowIconAccentFill = accentFill
    static let rowIconAccentGlyph = accent
    static let rowIconSuccessFill = affordanceFillGreen
    static let rowIconSuccessGlyph = pair(0x248A3D, 0x4FE070)
    static let rowIconNeutralFill = controlTrackFill
    static let rowIconNeutralGlyph = labelTertiary
    static let rowDividerInset: CGFloat = 53
    static let skeletonBarPrimary = pair(0x767680, 0x767680, lightAlpha: 0.14, darkAlpha: 0.22)
    static let skeletonBarSecondary = pair(0x767680, 0x767680, lightAlpha: 0.10, darkAlpha: 0.16)

    // MARK: - Request Overview: WebSocket panel — request-overview-tokens.md §5

    static let wsLiveDot = pair(0x34C759, 0x30D158)
    static let wsLiveDotHalo = pair(0x34C759, 0x30D158, lightAlpha: 0.18, darkAlpha: 0.18)
    static let wsClosedDot = labelTertiary
    static let sparkReceived = pair(0x34C759, 0x30D158)
    static let sparkSent = accent
    static let sparkEmpty = neutralFill
    static let statValueReceived = pair(0x248A3D, 0x30D158)
    static let statValueSent = accent
    static let statValueRate = labelPrimary
    static let chipRecvFill = pair(0x34C759, 0x30D158)
    static let chipRecvLabel = pair(0x00250C, 0x00250C)
    static let chipSentFill = accent
    static let chipSentLabel = pair(0xFFFFFF, 0xFFFFFF)
    static let chipPingFill = neutralFill
    static let chipPingLabel = labelSecondary
    static let chipCloseFill = pair(0xFF3B30, 0xFF453A, lightAlpha: 0.16, darkAlpha: 0.22)
    static let chipCloseLabel = statusMidRed

    // MARK: - Request Overview: fonts — request-overview-tokens.md §6

    static var bandMethodChipFont: PlatformFont { monospaced(11, weight: .semibold) }
    static var bandCaptionFont: PlatformFont { system(12, weight: .medium) }
    static var bandNumeralFont: PlatformFont { monospaced(44, weight: .bold) }
    static var bandReasonFont: PlatformFont { system(20, weight: .semibold) }
    static var bandWordFont: PlatformFont { system(34, weight: .bold) }
    static var bandWordFontCompact: PlatformFont { system(30, weight: .bold) }
    static var bandErrorCodeFont: PlatformFont { monospaced(15, weight: .semibold) }
    static var bandDurationFont: PlatformFont { system(24, weight: .bold) }
    static var bandDurationFontMono: PlatformFont { monospaced(24, weight: .bold) }
    static var bandUptimeFont: PlatformFont { monospaced(22, weight: .bold) }
    static var bandSubLineFont: PlatformFont { system(13, weight: .regular) }
    static var pathFont: PlatformFont { monospaced(16, weight: .semibold) }
    static var pathHostFont: PlatformFont { system(13, weight: .regular) }
    static var errorHeadlineFont: PlatformFont { system(15, weight: .semibold) }
    static var errorCodeFont: PlatformFont { monospaced(13, weight: .regular) }
    static var errorButtonFont: PlatformFont { system(14, weight: .medium) }
    static var cardTitleFont: PlatformFont { system(13, weight: .semibold) }
    static var cardAccessoryFont: PlatformFont { monospaced(12, weight: .medium) }
    static var cardRowLabelFont: PlatformFont { system(13, weight: .regular) }
    static var cardRowValueFont: PlatformFont { monospaced(13, weight: .medium) }
    static var detailRowTitleFont: PlatformFont { system(16, weight: .regular) }
    static var detailRowAccessoryFont: PlatformFont { system(15, weight: .regular) }
    static var overviewBadgeFont: PlatformFont { monospaced(10, weight: .semibold) }
    static var tileValueFont: PlatformFont { system(22, weight: .bold) }
    static var tileValueFontCompact: PlatformFont { system(15, weight: .semibold) }
    static var tileDetailFont: PlatformFont { monospaced(12, weight: .regular) }
    static var tileDetailFontSystem: PlatformFont { system(12, weight: .regular) }
    static var tileDimmedFont: PlatformFont { system(14, weight: .regular) }
    static var tileSkeletonLabelFont: PlatformFont { system(13, weight: .regular) }
    static var wsStatValueFont: PlatformFont { monospaced(19, weight: .semibold) }
    static var wsStatCaptionFont: PlatformFont { system(11, weight: .regular) }
    static var wsWindowLabelFont: PlatformFont { monospaced(11, weight: .regular) }
    static var wsSeeAllFont: PlatformFont { system(12, weight: .regular) }
    static var wsChipFont: PlatformFont { monospaced(10, weight: .semibold) }
    static var wsMessageMetaFont: PlatformFont { monospaced(11, weight: .regular) }
    static var wsMessageBodyFont: PlatformFont { monospaced(12, weight: .regular) }
    static var footerButtonFont: PlatformFont { system(16, weight: .medium) }

    // MARK: - Request Overview: metrics — request-overview-tokens.md §7

    static let bandPaddingTop: CGFloat = 6
    static let bandPaddingHorizontal: CGFloat = 20
    static let bandPaddingBottomWide: CGFloat = 20
    static let bandPaddingBottomCompact: CGFloat = 18
    static let bandStackGapWide: CGFloat = 14
    static let bandStackGapCompact: CGFloat = 13
    static let bandTopRowGap: CGFloat = 12
    static let bandLeadingColumnGap: CGFloat = 6
    static let bandLeadingColumnGapCompact: CGFloat = 7
    static let bandBadgeRowGap: CGFloat = 8
    static let bandStatusRowGap: CGFloat = 9
    static let bandStatusRowGapWide: CGFloat = 10
    static let bandTrailingColumnGap: CGFloat = 4
    static let methodChipCornerRadius: CGFloat = 6
    static let methodChipPaddingVertical: CGFloat = 5
    static let methodChipPaddingHorizontal: CGFloat = 7
    static let liveDotSize: CGFloat = 9
    static let liveDotHaloRadius: CGFloat = 5
    static let pathCardCornerRadius: CGFloat = 12
    static let pathCardPadding: CGFloat = 12
    static let pathCardGap: CGFloat = 11
    static let pathTextGap: CGFloat = 4
    static let copyTileSize: CGFloat = 32
    static let copyTileCornerRadius: CGFloat = 8
    static let copyTileGlyphSize: CGFloat = 16
    static let copyTileGlyphStrokeWidth: CGFloat = 1.6
    static let errorCardCornerRadius: CGFloat = 12
    static let errorCardPadding: CGFloat = 12
    static let errorCardGap: CGFloat = 8
    static let errorButtonRowTopPadding: CGFloat = 2
    static let errorButtonHeight: CGFloat = 34
    static let errorButtonCornerRadius: CGFloat = 9
    static let contentGapStandard: CGFloat = 18
    static let contentGapWebSocket: CGFloat = 14
    static let contentPaddingTopStandard: CGFloat = 18
    static let contentPaddingTopWebSocket: CGFloat = 16
    static let contentPaddingHorizontal: CGFloat = 16
    static let contentPaddingBottom: CGFloat = 18
    static let overviewCardCornerRadius: CGFloat = 14
    static let overviewCardPadding: CGFloat = 14
    static let overviewCardGap: CGFloat = 10
    static let timingRowGap: CGFloat = 7
    static let detailRowPaddingVertical: CGFloat = 11
    static let detailRowPaddingHorizontal: CGFloat = 14
    static let detailRowGap: CGFloat = 11
    static let detailRowIconSize: CGFloat = 28
    static let detailRowIconCornerRadius: CGFloat = 7
    static let detailRowGlyphSize: CGFloat = 15
    static let detailRowGlyphStrokeWidth: CGFloat = 1.6
    static let detailRowAccessoryGap: CGFloat = 7
    static let detailDividerWidth: CGFloat = 0.5
    static let detailDividerInset: CGFloat = 53
    static let chevronWidth: CGFloat = 8
    static let chevronHeight: CGFloat = 14
    static let chevronStrokeWidth: CGFloat = 2
    static let overviewBadgeCornerRadius: CGFloat = 5
    static let overviewBadgePaddingVertical: CGFloat = 4
    static let overviewBadgePaddingHorizontal: CGFloat = 6
    static let statTileMinHeight: CGFloat = 96
    static let statTilePadding: CGFloat = 13
    static let statTileGap: CGFloat = 9
    static let statTileHeaderGap: CGFloat = 7
    static let statTileGlyphSize: CGFloat = 15
    static let statTileChevronWidth: CGFloat = 7
    static let statTileChevronHeight: CGFloat = 12
    static let statGridSpacing: CGFloat = 10
    static let skeletonBarHeight: CGFloat = 11
    static let skeletonBarCornerRadius: CGFloat = 4
    static let skeletonBarGap: CGFloat = 6
    static let skeletonBarWidthPrimary: CGFloat = 0.58
    static let skeletonBarWidthSecondary: CGFloat = 0.34
    static let skeletonRowGap: CGFloat = 10
    static let wsStatTileCornerRadius: CGFloat = 12
    static let wsStatTilePadding: CGFloat = 11
    static let wsStatTileGap: CGFloat = 5
    static let sparkCardCornerRadius: CGFloat = 12
    static let sparkCardPadding: CGFloat = 12
    static let sparkCardGap: CGFloat = 8
    static let sparkHeight: CGFloat = 34
    static let sparkBarGap: CGFloat = 3
    static let sparkBarCornerRadius: CGFloat = 2
    static let sparkBucketCount: Int = 14
    static let sparkMinHeightFraction: Double = 0.08
    static let sparkWindowSeconds: TimeInterval = 240
    static let messagesHeaderGap: CGFloat = 8
    static let messagesHeaderPaddingHorizontal: CGFloat = 4
    static let messagePreviewCount: Int = 3
    static let messageCardCornerRadius: CGFloat = 12
    static let messageCardPaddingVertical: CGFloat = 11
    static let messageCardPaddingHorizontal: CGFloat = 12
    static let messageCardGap: CGFloat = 5
    static let messageCardStackGap: CGFloat = 8
    static let messageHeaderGap: CGFloat = 7
    static let messageBodyLineLimit: Int = 2
    static let wsChipCornerRadius: CGFloat = 4
    static let wsChipPaddingVertical: CGFloat = 3
    static let wsChipPaddingHorizontal: CGFloat = 5
    static let footerButtonHeight: CGFloat = 44
    static let footerButtonCornerRadius: CGFloat = 12
    static let minimumHitTarget: CGFloat = 44

    // MARK: - Request Overview: behavioral constants — request-overview-tokens.md §8

    /// Single live-tick period for the whole overview screen (§10, F1) — the hoisted
    /// `TimelineView` in `AtlantisTrafficDetailView` drives the band, the timing card,
    /// and (for `.websocket`) the WebSocket panel's counts/bytes/sparkline off this one
    /// clock, satisfying the ≤10 Hz count bound and the ≤1 Hz sparkline bound.
    static let elapsedTickInterval: TimeInterval = 1
}

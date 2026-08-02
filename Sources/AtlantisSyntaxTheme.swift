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
}

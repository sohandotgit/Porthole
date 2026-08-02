//
//  AtlantisOverviewBandView.swift
//  atlantis
//
//  Request Overview header band (design/request-overview-ui.md §3, §9.2).
//  Owns its own fill + hairline only; the screen root (R7) owns the
//  toolbar/status-bar bleed and the shared toolbar modifier stack (§9.1).
//

#if canImport(SwiftUI)
import SwiftUI

struct AtlantisOverviewBandView: View {
    let model: AtlantisOverviewModel
    /// Pre-formatted live value from the screen root's single `TimelineView` (§10);
    /// `nil` when `model.isLive` is false.
    let liveValue: String?

    private var family: AtlantisStatusFamily { model.family }

    /// `.pending` / `.websocket` use the compact padding + gap set (§3).
    private var isCompact: Bool {
        family == .pending || family == .websocket
    }

    var body: some View {
        bandContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(AtlantisSyntaxTheme.bandFill(family))
                    .ignoresSafeArea(edges: .top)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(AtlantisSyntaxTheme.bandHairline(family)))
                    .frame(height: AtlantisSyntaxTheme.bandHairlineWidth)
            }
    }

    private var bandContent: some View {
        VStack(
            alignment: .leading,
            spacing: isCompact ? AtlantisSyntaxTheme.bandStackGapCompact : AtlantisSyntaxTheme.bandStackGapWide
        ) {
            topRow
            if family == .transportError {
                errorCard
            }
            pathCard
        }
        .padding(.top, AtlantisSyntaxTheme.bandPaddingTop)
        .padding(.horizontal, AtlantisSyntaxTheme.bandPaddingHorizontal)
        .padding(.bottom, isCompact ? AtlantisSyntaxTheme.bandPaddingBottomCompact : AtlantisSyntaxTheme.bandPaddingBottomWide)
    }

    // MARK: - Top row (§3.1)

    private var topRow: some View {
        HStack(alignment: .bottom, spacing: AtlantisSyntaxTheme.bandTopRowGap) {
            leadingColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            trailingColumn
        }
    }

    // MARK: - Leading column: badge row + status block (§3.2-§3.4)

    private var leadingColumn: some View {
        VStack(
            alignment: .leading,
            spacing: isCompact ? AtlantisSyntaxTheme.bandLeadingColumnGapCompact : AtlantisSyntaxTheme.bandLeadingColumnGap
        ) {
            badgeRow
            statusBlock
        }
    }

    private var badgeRow: some View {
        HStack(spacing: AtlantisSyntaxTheme.bandBadgeRowGap) {
            Text(model.methodBadge)
                .font(Font(AtlantisSyntaxTheme.bandMethodChipFont))
                .tracking(0.8)
                .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
                .padding(.vertical, AtlantisSyntaxTheme.methodChipPaddingVertical)
                .padding(.horizontal, AtlantisSyntaxTheme.methodChipPaddingHorizontal)
                .background(Color(AtlantisSyntaxTheme.chipFill(family)))
                .cornerRadius(AtlantisSyntaxTheme.methodChipCornerRadius)
            Text(model.caption)
                .font(Font(AtlantisSyntaxTheme.bandCaptionFont))
                .tracking(0.3)
                .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(family)))
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch family {
        case .success, .clientError, .serverError:
            HStack(alignment: .firstTextBaseline, spacing: AtlantisSyntaxTheme.bandStatusRowGap) {
                Text(model.statusNumeral ?? "")
                    .font(Font(AtlantisSyntaxTheme.bandNumeralFont))
                    .tracking(-1.5)
                    .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
                if let reasonWord = model.reasonWord {
                    Text(reasonWord)
                        .font(Font(AtlantisSyntaxTheme.bandReasonFont))
                        .tracking(-0.3)
                        .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(family)))
                }
            }
        case .transportError:
            HStack(alignment: .firstTextBaseline, spacing: AtlantisSyntaxTheme.bandStatusRowGapWide) {
                Text(model.statusWord ?? "")
                    .font(Font(AtlantisSyntaxTheme.bandWordFont))
                    .tracking(-0.8)
                    .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
                if let code = model.statusNumeral {
                    Text(code)
                        .font(Font(AtlantisSyntaxTheme.bandErrorCodeFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(family)))
                }
            }
        case .pending:
            Text(model.statusWord ?? "")
                .font(Font(AtlantisSyntaxTheme.bandWordFontCompact))
                .tracking(-0.7)
                .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
        case .websocket:
            HStack(alignment: .center, spacing: AtlantisSyntaxTheme.bandStatusRowGapWide) {
                livenessDot
                Text(model.statusWord ?? "")
                    .font(Font(AtlantisSyntaxTheme.bandWordFontCompact))
                    .tracking(-0.7)
                    .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
            }
        }
    }

    private var livenessDot: some View {
        Circle()
            .fill(Color(model.isConnected ? AtlantisSyntaxTheme.wsLiveDot : AtlantisSyntaxTheme.wsClosedDot))
            .frame(width: AtlantisSyntaxTheme.liveDotSize, height: AtlantisSyntaxTheme.liveDotSize)
            .background {
                if model.isConnected {
                    let haloDiameter = AtlantisSyntaxTheme.liveDotSize + AtlantisSyntaxTheme.liveDotHaloRadius * 2
                    Circle()
                        .fill(Color(AtlantisSyntaxTheme.wsLiveDotHalo))
                        .frame(width: haloDiameter, height: haloDiameter)
                }
            }
    }

    // MARK: - Trailing column: duration value + sub-line (§3.5)

    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: AtlantisSyntaxTheme.bandTrailingColumnGap) {
            trailingValue
                .font(trailingValueFont)
                .tracking(family == .websocket ? 0 : -0.5)
                .foregroundColor(Color(AtlantisSyntaxTheme.statusDeep(family)))
            Text(model.subLine)
                .font(Font(AtlantisSyntaxTheme.bandSubLineFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(family)))
        }
    }

    private var trailingValueFont: Font {
        switch family {
        case .success, .clientError, .serverError, .transportError:
            return Font(AtlantisSyntaxTheme.bandDurationFont)
        case .pending:
            return Font(AtlantisSyntaxTheme.bandDurationFontMono)
        case .websocket:
            return Font(AtlantisSyntaxTheme.bandUptimeFont)
        }
    }

    /// Reads the screen root's single `TimelineView` value (§10) — no timer here.
    private var trailingValue: some View {
        Text(liveValue ?? model.durationValue)
    }

    // MARK: - Path / host card (§3.6)

    private var pathCard: some View {
        HStack(alignment: .center, spacing: AtlantisSyntaxTheme.pathCardGap) {
            VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.pathTextGap) {
                Text(model.pathText)
                    .font(Font(AtlantisSyntaxTheme.pathFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                    .lineLimit(nil)
                if !model.hostText.isEmpty {
                    Text(model.hostText)
                        .font(Font(AtlantisSyntaxTheme.pathHostFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.hostLabel(family)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            copyTile
        }
        .padding(family == .transportError ? 0 : AtlantisSyntaxTheme.pathCardPadding)
        .background {
            if family != .transportError {
                Color(AtlantisSyntaxTheme.pathCardFill)
                    .cornerRadius(AtlantisSyntaxTheme.pathCardCornerRadius)
            }
        }
    }

    private var copyTile: some View {
        Button {
            AtlantisPasteboard.copy(model.package.request.url)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: AtlantisSyntaxTheme.copyTileGlyphSize, weight: .regular))
                .foregroundColor(Color(AtlantisSyntaxTheme.affordanceGlyph(family)))
                .frame(width: AtlantisSyntaxTheme.copyTileSize, height: AtlantisSyntaxTheme.copyTileSize)
                .background(Color(AtlantisSyntaxTheme.affordanceFill(family)))
                .cornerRadius(AtlantisSyntaxTheme.copyTileCornerRadius)
        }
        .buttonStyle(.plain)
        .frame(minWidth: AtlantisSyntaxTheme.minimumHitTarget, minHeight: AtlantisSyntaxTheme.minimumHitTarget)
        .contentShape(Rectangle())
    }

    // MARK: - Error card (§3.7, `.transportError` only)

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.errorCardGap) {
            Text(model.errorHeadline ?? "")
                .font(Font(AtlantisSyntaxTheme.errorHeadlineFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.errorHeadline))
            Text(model.errorCodeLine ?? "")
                .font(Font(AtlantisSyntaxTheme.errorCodeFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.errorCode))
                .lineLimit(nil)
            Button {
                AtlantisPasteboard.copy("\(model.errorHeadline ?? "")\n\(model.errorCodeLine ?? "")")
            } label: {
                Text("Copy error")
                    .font(Font(AtlantisSyntaxTheme.errorButtonFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.errorButtonLabel))
                    .frame(maxWidth: .infinity)
                    .frame(height: AtlantisSyntaxTheme.errorButtonHeight)
                    .background(Color(AtlantisSyntaxTheme.errorButtonFill))
                    .cornerRadius(AtlantisSyntaxTheme.errorButtonCornerRadius)
            }
            .buttonStyle(.plain)
            .padding(.top, AtlantisSyntaxTheme.errorButtonRowTopPadding)
        }
        .padding(AtlantisSyntaxTheme.errorCardPadding)
        .background(Color(AtlantisSyntaxTheme.errorCardFill))
        .cornerRadius(AtlantisSyntaxTheme.errorCardCornerRadius)
    }
}
#endif

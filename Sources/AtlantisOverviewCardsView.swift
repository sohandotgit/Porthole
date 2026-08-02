//
//  AtlantisOverviewCardsView.swift
//  atlantis
//
//  Request Overview content cards: timing card, details card, stat-tile
//  grid (design/request-overview-ui.md §5-§7, design/request-overview-tokens.md,
//  Tests/request-overview.spec.md §4). Body rows are plain list rows that push
//  AtlantisBodyViewerView on tap, matching header rows.
//

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Timing card (§5)

struct AtlantisOverviewTimingCard: View {
    let model: AtlantisOverviewModel
    /// Pre-formatted live value from the screen root's single `TimelineView` (§10);
    /// `nil` when `model.isLive` is false.
    let liveValue: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.timingTitle)
                    .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                Spacer()
                if let accessory = model.timingAccessory {
                    Text(accessory)
                        .font(Font(AtlantisSyntaxTheme.cardAccessoryFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(model.family)))
                }
            }

            Rectangle()
                .fill(Color(AtlantisSyntaxTheme.divider))
                .frame(height: AtlantisSyntaxTheme.detailDividerWidth)
                .padding(.vertical, AtlantisSyntaxTheme.overviewCardGap)

            VStack(spacing: AtlantisSyntaxTheme.timingRowGap) {
                HStack {
                    Text("Started")
                        .font(Font(AtlantisSyntaxTheme.cardRowLabelFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
                    Spacer()
                    Text(model.startedText)
                        .font(Font(AtlantisSyntaxTheme.cardRowValueFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelHeading))
                }

                HStack {
                    Text(model.timingSecondRowLabel)
                        .font(Font(AtlantisSyntaxTheme.cardRowLabelFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
                    Spacer()
                    Text(liveValue ?? model.durationValue)
                        .font(Font(AtlantisSyntaxTheme.cardRowValueFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelHeading))
                }
            }
        }
        .padding(AtlantisSyntaxTheme.overviewCardPadding)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.overviewCardCornerRadius)
    }
}

// MARK: - Details card (§6)

struct AtlantisOverviewDetailsCard: View {
    let model: AtlantisOverviewModel

    private var rows: [AtlantisOverviewDetailRow] { model.detailRows }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rowView(row)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color(AtlantisSyntaxTheme.divider))
                        .frame(height: AtlantisSyntaxTheme.detailDividerWidth)
                        .padding(.leading, AtlantisSyntaxTheme.detailDividerInset)
                }
            }
        }
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.overviewCardCornerRadius)
        .clipped()
    }

    @ViewBuilder
    private func rowView(_ row: AtlantisOverviewDetailRow) -> some View {
        switch row.title {
        case "Request Headers" where row.isTappable:
            NavigationLink {
                AtlantisHeadersDetailView(title: "Request Headers", headers: model.package.request.headers)
            } label: {
                AtlantisOverviewDetailRowView(row: row)
            }
        case "Response Headers" where row.isTappable:
            NavigationLink {
                AtlantisHeadersDetailView(title: "Response Headers", headers: model.package.response?.headers ?? [])
            } label: {
                AtlantisOverviewDetailRowView(row: row)
            }
        case "Request Body" where row.isTappable:
            NavigationLink {
                AtlantisBodyViewerView(
                    title: "Request Body",
                    data: model.package.request.body ?? Data(),
                    contentType: AtlantisBodyClassifier.contentType(from: model.package.request.headers),
                    method: model.package.request.method,
                    side: .request,
                    statusCode: nil
                )
            } label: {
                AtlantisOverviewDetailRowView(row: row)
            }
        case "Response Body" where row.isTappable:
            NavigationLink {
                AtlantisBodyViewerView(
                    title: "Response Body",
                    data: model.package.responseBodyData,
                    contentType: AtlantisBodyClassifier.contentType(from: model.package.response?.headers ?? []),
                    method: model.package.request.method,
                    side: .response,
                    statusCode: model.package.response?.statusCode
                )
            } label: {
                AtlantisOverviewDetailRowView(row: row)
            }
        default:
            AtlantisOverviewDetailRowView(row: row)
        }
    }
}

private struct AtlantisOverviewDetailRowView: View {
    let row: AtlantisOverviewDetailRow
    var showsChevron: Bool = true

    private var iconFill: Color {
        switch row.iconKind {
        case .accent: return Color(AtlantisSyntaxTheme.rowIconAccentFill)
        case .success: return Color(AtlantisSyntaxTheme.rowIconSuccessFill)
        case .neutral: return Color(AtlantisSyntaxTheme.rowIconNeutralFill)
        }
    }

    private var iconGlyph: Color {
        switch row.iconKind {
        case .accent: return Color(AtlantisSyntaxTheme.rowIconAccentGlyph)
        case .success: return Color(AtlantisSyntaxTheme.rowIconSuccessGlyph)
        case .neutral: return Color(AtlantisSyntaxTheme.rowIconNeutralGlyph)
        }
    }

    private var glyphName: String {
        switch row.title {
        case "Request Headers", "Response Headers": return "list.bullet"
        default: return row.iconKind == .neutral ? "doc" : "cube"
        }
    }

    var body: some View {
        HStack(spacing: AtlantisSyntaxTheme.detailRowGap) {
            RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.detailRowIconCornerRadius)
                .fill(iconFill)
                .frame(width: AtlantisSyntaxTheme.detailRowIconSize, height: AtlantisSyntaxTheme.detailRowIconSize)
                .overlay(
                    Image(systemName: glyphName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: AtlantisSyntaxTheme.detailRowGlyphSize, height: AtlantisSyntaxTheme.detailRowGlyphSize)
                        .foregroundColor(iconGlyph)
                )

            Text(row.title)
                .font(Font(AtlantisSyntaxTheme.detailRowTitleFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)

            switch row.accessory {
            case .count(let count):
                Text("\(count)")
                    .font(Font(AtlantisSyntaxTheme.detailRowAccessoryFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            case .word(let word):
                Text(word)
                    .font(Font(AtlantisSyntaxTheme.detailRowAccessoryFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            case .badge(let badge, let size):
                HStack(spacing: AtlantisSyntaxTheme.detailRowAccessoryGap) {
                    Text(badge)
                        .font(Font(AtlantisSyntaxTheme.overviewBadgeFont))
                        .tracking(0.6)
                        .foregroundColor(Color(AtlantisSyntaxTheme.badgeForeground(for: badge)))
                        .padding(.vertical, AtlantisSyntaxTheme.overviewBadgePaddingVertical)
                        .padding(.horizontal, AtlantisSyntaxTheme.overviewBadgePaddingHorizontal)
                        .background(Color(AtlantisSyntaxTheme.badgeFill(for: badge)))
                        .cornerRadius(AtlantisSyntaxTheme.overviewBadgeCornerRadius)
                    Text(size)
                        .font(Font(AtlantisSyntaxTheme.detailRowAccessoryFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                }
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AtlantisSyntaxTheme.chevronWidth, height: AtlantisSyntaxTheme.chevronHeight)
                    .foregroundColor(Color(row.isTappable ? AtlantisSyntaxTheme.chevronPassive : AtlantisSyntaxTheme.chevronDimmed))
            }
        }
        .padding(.vertical, AtlantisSyntaxTheme.detailRowPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.detailRowPaddingHorizontal)
    }
}

// MARK: - Stat-tile grid (§7)

struct AtlantisOverviewStatGridView: View {
    let tiles: [AtlantisOverviewStatTile]

    private static let columns = [GridItem(.flexible(), spacing: AtlantisSyntaxTheme.statGridSpacing),
                                   GridItem(.flexible(), spacing: AtlantisSyntaxTheme.statGridSpacing)]

    /// `.gridCellColumns` only spans inside a real `Grid`; a `LazyVGrid` ignores it (B3).
    /// Split instead: paired tiles go in the 2-column grid, skeleton tiles render full width below.
    private var pairedTiles: [AtlantisOverviewStatTile] { tiles.filter { !$0.isSkeleton } }
    private var skeletonTiles: [AtlantisOverviewStatTile] { tiles.filter { $0.isSkeleton } }

    var body: some View {
        VStack(spacing: AtlantisSyntaxTheme.statGridSpacing) {
            if !pairedTiles.isEmpty {
                LazyVGrid(columns: Self.columns, spacing: AtlantisSyntaxTheme.statGridSpacing) {
                    ForEach(Array(pairedTiles.enumerated()), id: \.offset) { _, tile in
                        AtlantisOverviewStatTileView(tile: tile)
                    }
                }
            }
            ForEach(Array(skeletonTiles.enumerated()), id: \.offset) { _, tile in
                AtlantisOverviewStatTileView(tile: tile)
            }
        }
    }
}

private extension AtlantisOverviewStatTile {
    var isSkeleton: Bool {
        if case .skeleton = content { return true }
        return false
    }
}

private struct AtlantisOverviewStatTileView: View {
    let tile: AtlantisOverviewStatTile

    private var isDimmed: Bool {
        if case .dimmed = tile.content { return true }
        return false
    }

    var body: some View {
        switch tile.content {
        case .skeleton(let label):
            skeletonBody(label: label)
        case .dimmed(let phrase):
            dimmedBody(phrase: phrase)
        case .value(let value, let detail, let iconKind):
            liveBody(iconKind: iconKind) {
                Text(value)
                    .font(Font(AtlantisSyntaxTheme.tileValueFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
            } detailView: {
                if let detail = detail {
                    Text(detail)
                        .font(Font(AtlantisSyntaxTheme.tileDetailFont))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        case .badge(let badge, let size, let detail, let iconKind):
            liveBody(iconKind: iconKind) {
                HStack(spacing: AtlantisSyntaxTheme.detailRowAccessoryGap) {
                    Text(badge)
                        .font(Font(AtlantisSyntaxTheme.overviewBadgeFont))
                        .tracking(0.6)
                        .foregroundColor(Color(AtlantisSyntaxTheme.badgeForeground(for: badge)))
                        .padding(.vertical, AtlantisSyntaxTheme.overviewBadgePaddingVertical)
                        .padding(.horizontal, AtlantisSyntaxTheme.overviewBadgePaddingHorizontal)
                        .background(Color(AtlantisSyntaxTheme.badgeFill(for: badge)))
                        .cornerRadius(AtlantisSyntaxTheme.overviewBadgeCornerRadius)
                    Text(size)
                        .font(Font(AtlantisSyntaxTheme.tileValueFontCompact))
                        .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                }
            } detailView: {
                if let detail = detail {
                    Text(detail)
                        .font(Font(AtlantisSyntaxTheme.tileDetailFontSystem))
                        .foregroundColor(Color(AtlantisSyntaxTheme.statusMid(.pending)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private func liveBody<Value: View, Detail: View>(
        iconKind: AtlantisOverviewDetailRow.IconKind,
        @ViewBuilder value: () -> Value,
        @ViewBuilder detailView: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.statTileGap) {
            HStack(spacing: AtlantisSyntaxTheme.statTileHeaderGap) {
                Image(systemName: iconKind == .accent ? "cube" : "doc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AtlantisSyntaxTheme.statTileGlyphSize, height: AtlantisSyntaxTheme.statTileGlyphSize)
                    .foregroundColor(Color(iconKind == .accent ? AtlantisSyntaxTheme.rowIconAccentGlyph : AtlantisSyntaxTheme.rowIconSuccessGlyph))
                Text(tile.title)
                    .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // No tap is wired for stat tiles — dropped chevron rather than a dead
                // affordance (F3). Revisit if tiles gain real navigation.
            }
            value()
            detailView()
        }
        .padding(AtlantisSyntaxTheme.statTilePadding)
        .frame(minHeight: AtlantisSyntaxTheme.statTileMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.overviewCardCornerRadius)
    }

    @ViewBuilder
    private func dimmedBody(phrase: String) -> some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.statTileGap) {
            HStack(spacing: AtlantisSyntaxTheme.statTileHeaderGap) {
                Image(systemName: "doc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AtlantisSyntaxTheme.statTileGlyphSize, height: AtlantisSyntaxTheme.statTileGlyphSize)
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                Text(tile.title)
                    .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(phrase)
                .font(Font(AtlantisSyntaxTheme.tileDimmedFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(AtlantisSyntaxTheme.statTilePadding)
        .frame(minHeight: AtlantisSyntaxTheme.statTileMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.overviewCardCornerRadius)
    }

    @ViewBuilder
    private func skeletonBody(label: String) -> some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.statTileGap) {
            HStack(spacing: AtlantisSyntaxTheme.statTileHeaderGap) {
                Image(systemName: "doc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AtlantisSyntaxTheme.statTileGlyphSize, height: AtlantisSyntaxTheme.statTileGlyphSize)
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                Text(tile.title)
                    .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: AtlantisSyntaxTheme.skeletonRowGap) {
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.skeletonBarGap) {
                        RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.skeletonBarCornerRadius)
                            .fill(Color(AtlantisSyntaxTheme.skeletonBarPrimary))
                            .frame(width: proxy.size.width * AtlantisSyntaxTheme.skeletonBarWidthPrimary,
                                   height: AtlantisSyntaxTheme.skeletonBarHeight)
                        RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.skeletonBarCornerRadius)
                            .fill(Color(AtlantisSyntaxTheme.skeletonBarSecondary))
                            .frame(width: proxy.size.width * AtlantisSyntaxTheme.skeletonBarWidthSecondary,
                                   height: AtlantisSyntaxTheme.skeletonBarHeight)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(label)
                    .font(Font(AtlantisSyntaxTheme.tileSkeletonLabelFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            }
        }
        .padding(AtlantisSyntaxTheme.statTilePadding)
        .frame(minHeight: AtlantisSyntaxTheme.statTileMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.overviewCardCornerRadius)
    }
}

// MARK: - Badge color lookup by badge string (D9 — reuses body-viewer badge tokens)

private extension AtlantisSyntaxTheme {
    static func badgeForeground(for badge: String) -> PlatformColor {
        switch badge {
        case "JSON": return badgeJSONForeground
        case "XML": return badgeXMLForeground
        case "HTML": return badgeHTMLForeground
        case "FORM": return badgeFormForeground
        case "IMAGE": return badgeImageForeground
        case "TEXT": return badgeTextForeground
        default: return badgeBinaryForeground
        }
    }

    static func badgeFill(for badge: String) -> PlatformColor {
        switch badge {
        case "JSON": return badgeJSONFill
        case "XML": return badgeXMLFill
        case "HTML": return badgeHTMLFill
        case "FORM": return badgeFormFill
        case "IMAGE": return badgeImageFill
        case "TEXT": return badgeTextFill
        default: return badgeBinaryFill
        }
    }
}
#endif

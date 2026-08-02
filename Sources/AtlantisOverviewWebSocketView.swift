//
//  AtlantisOverviewWebSocketView.swift
//  atlantis
//
//  WebSocket panel for the Request Overview screen (design/request-overview-ui.md §8,
//  design/request-overview-tokens.md §5, Tests/request-overview.spec.md §3-4). Every count,
//  byte total, rate, and sparkline bucket comes from `AtlantisOverviewModel` — this view
//  formats and lays out, it does not compute.
//

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Panel root (§8.1-§8.4)

struct AtlantisOverviewWebSocketView: View {
    let model: AtlantisOverviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.contentGapWebSocket) {
            statTileRow
            sparklineCard
            if let seeAllLabel = model.seeAllLabel {
                messagesHeader(seeAllLabel: seeAllLabel)
            }
            messagePreviewStack
        }
    }

    // MARK: - 3-up stat tiles (§8.1)

    private static let statColumns = [GridItem(.flexible(), spacing: AtlantisSyntaxTheme.statGridSpacing),
                                       GridItem(.flexible(), spacing: AtlantisSyntaxTheme.statGridSpacing),
                                       GridItem(.flexible(), spacing: AtlantisSyntaxTheme.statGridSpacing)]

    private var statTileRow: some View {
        LazyVGrid(columns: Self.statColumns, spacing: AtlantisSyntaxTheme.statGridSpacing) {
            statTile(value: "\(model.receivedCount)", valueColor: AtlantisSyntaxTheme.statValueReceived,
                     captionLine1: "received", captionLine2: model.receivedBytesText)
            statTile(value: "\(model.sentCount)", valueColor: AtlantisSyntaxTheme.statValueSent,
                     captionLine1: "sent", captionLine2: model.sentBytesText)
            statTile(value: model.rateText, valueColor: AtlantisSyntaxTheme.statValueRate,
                     captionLine1: "rate", captionLine2: "last 60 s")
        }
    }

    private func statTile(value: String, valueColor: AtlantisSyntaxTheme.PlatformColor,
                           captionLine1: String, captionLine2: String) -> some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.wsStatTileGap) {
            Text(value)
                .font(Font(AtlantisSyntaxTheme.wsStatValueFont))
                .foregroundColor(Color(valueColor))
            VStack(alignment: .leading, spacing: 0) {
                Text(captionLine1)
                Text(captionLine2)
            }
            .font(Font(AtlantisSyntaxTheme.wsStatCaptionFont))
            .foregroundColor(Color(AtlantisSyntaxTheme.labelSecondary))
        }
        .padding(AtlantisSyntaxTheme.wsStatTilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.wsStatTileCornerRadius)
    }

    // MARK: - Frame-activity sparkline (§8.2)

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.sparkCardGap) {
            HStack {
                Text("Frame activity")
                    .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelHeading))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.sparklineWindowLabel)
                    .font(Font(AtlantisSyntaxTheme.wsWindowLabelFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            }
            HStack(alignment: .bottom, spacing: AtlantisSyntaxTheme.sparkBarGap) {
                ForEach(Array(model.sparkline.enumerated()), id: \.offset) { _, bucket in
                    RoundedRectangle(cornerRadius: AtlantisSyntaxTheme.sparkBarCornerRadius)
                        .fill(Color(sparkBarColor(bucket.direction)))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(1, bucket.heightFraction * AtlantisSyntaxTheme.sparkHeight))
                }
            }
            .frame(height: AtlantisSyntaxTheme.sparkHeight, alignment: .bottom)
        }
        .padding(AtlantisSyntaxTheme.sparkCardPadding)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.sparkCardCornerRadius)
    }

    private func sparkBarColor(_ direction: AtlantisSparklineBucket.Direction) -> AtlantisSyntaxTheme.PlatformColor {
        switch direction {
        case .received: return AtlantisSyntaxTheme.sparkReceived
        case .sent: return AtlantisSyntaxTheme.sparkSent
        case .none: return AtlantisSyntaxTheme.sparkEmpty
        }
    }

    // MARK: - Messages header (§8.3)

    private func messagesHeader(seeAllLabel: String) -> some View {
        HStack(spacing: AtlantisSyntaxTheme.messagesHeaderGap) {
            Text("Messages")
                .font(Font(AtlantisSyntaxTheme.cardTitleFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink(destination: AtlantisMessageListView(messages: model.websocketMessages)) {
                Text(seeAllLabel)
                    .font(Font(AtlantisSyntaxTheme.wsSeeAllFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.accent))
            }
        }
        .padding(.horizontal, AtlantisSyntaxTheme.messagesHeaderPaddingHorizontal)
    }

    // MARK: - Message preview cards (§8.4)

    private var messagePreviewStack: some View {
        VStack(spacing: AtlantisSyntaxTheme.messageCardStackGap) {
            ForEach(Array(messagePreviewPairs.enumerated()), id: \.offset) { _, pair in
                NavigationLink(destination: AtlantisMessageDetailView(message: pair.message)) {
                    messagePreviewCard(pair.preview)
                }
            }
        }
    }

    /// Pairs each formatted preview with its source message so a tap can push
    /// `AtlantisMessageDetailView`. Mirrors `model.messagePreviews`' own newest-first,
    /// last-`messagePreviewCount` slice exactly — no formatting or bucketing happens here.
    private var messagePreviewPairs: [(preview: AtlantisOverviewMessagePreview, message: WebsocketMessagePackage)] {
        let messages = model.websocketMessages
        let count = min(AtlantisSyntaxTheme.messagePreviewCount, messages.count)
        guard count > 0 else { return [] }
        let recentMessages = Array(messages.suffix(count).reversed())
        return Array(zip(model.messagePreviews, recentMessages))
    }

    private func messagePreviewCard(_ preview: AtlantisOverviewMessagePreview) -> some View {
        VStack(alignment: .leading, spacing: AtlantisSyntaxTheme.messageCardGap) {
            HStack(spacing: AtlantisSyntaxTheme.messageHeaderGap) {
                Text(preview.chipLabel)
                    .font(Font(AtlantisSyntaxTheme.wsChipFont))
                    .tracking(0.5)
                    .foregroundColor(Color(chipLabelColor(preview.messageType)))
                    .padding(.vertical, AtlantisSyntaxTheme.wsChipPaddingVertical)
                    .padding(.horizontal, AtlantisSyntaxTheme.wsChipPaddingHorizontal)
                    .background(Color(chipFillColor(preview.messageType)))
                    .cornerRadius(AtlantisSyntaxTheme.wsChipCornerRadius)
                Text(preview.timestampText)
                    .font(Font(AtlantisSyntaxTheme.wsMessageMetaFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(preview.sizeText)
                    .font(Font(AtlantisSyntaxTheme.wsMessageMetaFont))
                    .foregroundColor(Color(AtlantisSyntaxTheme.labelTertiary))
            }
            Text(preview.bodyPreview)
                .font(Font(AtlantisSyntaxTheme.wsMessageBodyFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.labelHeading))
                .lineLimit(AtlantisSyntaxTheme.messageBodyLineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AtlantisSyntaxTheme.messageCardPaddingVertical)
        .padding(.horizontal, AtlantisSyntaxTheme.messageCardPaddingHorizontal)
        .background(Color(AtlantisSyntaxTheme.cardFill))
        .cornerRadius(AtlantisSyntaxTheme.messageCardCornerRadius)
    }

    private func chipFillColor(_ type: WebsocketMessagePackage.MessageType) -> AtlantisSyntaxTheme.PlatformColor {
        switch type {
        case .receive: return AtlantisSyntaxTheme.chipRecvFill
        case .send: return AtlantisSyntaxTheme.chipSentFill
        case .pingPong: return AtlantisSyntaxTheme.chipPingFill
        case .sendCloseMessage: return AtlantisSyntaxTheme.chipCloseFill
        }
    }

    private func chipLabelColor(_ type: WebsocketMessagePackage.MessageType) -> AtlantisSyntaxTheme.PlatformColor {
        switch type {
        case .receive: return AtlantisSyntaxTheme.chipRecvLabel
        case .send: return AtlantisSyntaxTheme.chipSentLabel
        case .pingPong: return AtlantisSyntaxTheme.chipPingLabel
        case .sendCloseMessage: return AtlantisSyntaxTheme.chipCloseLabel
        }
    }
}

// MARK: - Full message list (§8.3, additive — pushed from "See all N")

struct AtlantisMessageListView: View {
    let messages: [WebsocketMessagePackage]

    var body: some View {
        List(Array(messages.enumerated()), id: \.offset) { _, message in
            AtlantisMessageRowView(message: message)
        }
        .navigationTitle("Messages")
    }
}
#endif

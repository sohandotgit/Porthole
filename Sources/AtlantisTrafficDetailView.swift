//
//  AtlantisTrafficDetailView.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private func atlantisContentType(from headers: [Header]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
}

private func atlantisHumanBytes(_ count: Int) -> String {
    AtlantisFormat.bytes(count)
}

/// Highlights `query` matches in `text` with a yellow background.
private func atlantisHighlighted(_ text: String, query: String) -> AttributedString {
    var attributed = AttributedString(text)
    let ranges = AtlantisBodySearch.matchRanges(in: text, query: query)
    for range in ranges {
        if let attributedRange = Range(range, in: attributed) {
            attributed[attributedRange].backgroundColor = .yellow
        }
    }
    return attributed
}

private struct AtlantisHeadersSectionView: View {
    let title: String
    let headers: [Header]
    @Binding var query: String

    private var matchCount: Int {
        headers.reduce(0) { $0 + AtlantisBodySearch.matchCount(in: "\($1.key): \($1.value)", query: query) }
    }

    var body: some View {
        Section(query.isEmpty ? title : "\(title) (\(matchCount))") {
            if headers.isEmpty {
                Text("No headers")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(atlantisHighlighted(header.key, query: query))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text(atlantisHighlighted(header.value, query: query))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct AtlantisHeadersDetailView: View {
    let title: String
    let headers: [Header]

    @State private var query: String = ""

    var body: some View {
        List {
            AtlantisHeadersSectionView(title: title, headers: headers, query: $query)
        }
        .searchable(text: $query)
        .navigationTitle(title)
    }
}

struct AtlantisMessageDetailView: View {
    let message: WebsocketMessagePackage

    private var data: Data {
        if let string = message.stringValue {
            return Data(string.utf8)
        }
        return message.dataValue ?? Data()
    }

    var body: some View {
        AtlantisBodyViewerView(title: "Message", data: data, contentType: nil,
                                method: "", side: .response, statusCode: nil)
    }
}

struct AtlantisMessageRowView: View {
    let message: WebsocketMessagePackage

    private var directionInfo: (label: String, systemImage: String, color: Color) {
        switch message.messageType {
        case .send: return ("send", "arrow.up", .blue)
        case .receive: return ("receive", "arrow.down", .green)
        case .pingPong: return ("ping", "arrow.left.arrow.right", .gray)
        case .sendCloseMessage: return ("close", "xmark", .red)
        }
    }

    private var content: String {
        if let string = message.stringValue { return string }
        if let data = message.dataValue {
            return String(data: data, encoding: .utf8) ?? "⟨binary, \(data.count) bytes⟩"
        }
        return ""
    }

    private var sizeText: String {
        if let string = message.stringValue {
            return atlantisHumanBytes(string.utf8.count)
        }
        return atlantisHumanBytes(message.dataValue?.count ?? 0)
    }

    var body: some View {
        NavigationLink(destination: AtlantisMessageDetailView(message: message)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: directionInfo.systemImage)
                        .foregroundColor(directionInfo.color)
                    Text(directionInfo.label)
                        .font(.caption.bold())
                        .foregroundColor(directionInfo.color)
                    Spacer()
                    Text(AtlantisFormat.time(message.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(content)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2)
                Text(sizeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Detail view for a single `TrafficPackage` — the Request Overview screen
/// (design/request-overview-ui.md §11): header band, timing card, and a
/// family-specific content region, composed from `AtlantisOverviewModel`.
public struct AtlantisTrafficDetailView: View {

    private let package: TrafficPackage

    @State private var showsShareSheet = false
    @State private var shareItems: [Any] = []

    public init(package: TrafficPackage) {
        self.package = package
    }

    private var model: AtlantisOverviewModel {
        AtlantisOverviewModel(package: package, now: Date().timeIntervalSince1970)
    }

    public var body: some View {
        let model = self.model
        ScrollView {
            VStack(spacing: 0) {
                if model.isLive {
                    // Single TimelineView for the whole live screen (§10) — rebuilding the
                    // model each tick is what makes the WebSocket panel's counts/bytes/
                    // sparkline actually refresh at 1 Hz instead of freezing at push time (F1).
                    TimelineView(.periodic(from: .now, by: AtlantisSyntaxTheme.elapsedTickInterval)) { context in
                        let tickModel = AtlantisOverviewModel(package: package, now: context.date.timeIntervalSince1970)
                        let liveValue = tickModel.liveValue(now: context.date.timeIntervalSince1970)
                        AtlantisOverviewBandView(model: tickModel, liveValue: liveValue)
                        contentColumn(model: tickModel, liveValue: liveValue)
                    }
                } else {
                    AtlantisOverviewBandView(model: model, liveValue: nil)
                    contentColumn(model: model, liveValue: nil)
                }
            }
        }
        .background(Color(AtlantisSyntaxTheme.pageFill).ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .navigationTitle(model.navigationTitle)
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(AtlantisSyntaxTheme.bandFill(model.family)), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(model.bandChromeIsDark ? .dark : nil, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Share cURL") {
                        shareItems = [package.curlCommand()]
                        showsShareSheet = true
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .disabled(package.request.url.isEmpty)
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            AtlantisShareSheet(activityItems: shareItems)
        }
        #elseif os(macOS)
        .toolbarBackground(Color(AtlantisSyntaxTheme.bandFill(model.family)), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
    }

    // MARK: - Content column (§4, §11)

    @ViewBuilder
    private func contentColumn(model: AtlantisOverviewModel, liveValue: String?) -> some View {
        let isWebSocket = model.family == .websocket
        VStack(alignment: .leading, spacing: isWebSocket ? AtlantisSyntaxTheme.contentGapWebSocket : AtlantisSyntaxTheme.contentGapStandard) {
            AtlantisOverviewTimingCard(model: model, liveValue: liveValue)

            switch model.family {
            case .success, .clientError, .serverError:
                AtlantisOverviewDetailsCard(model: model)
            case .transportError:
                AtlantisOverviewStatGridView(tiles: model.statTiles(for: .transportError))
            case .pending:
                AtlantisOverviewStatGridView(tiles: model.statTiles(for: .pending))
            case .websocket:
                AtlantisOverviewWebSocketView(model: model)
            }

            if let action = model.footerAction {
                footerButton(action: action)
            }
        }
        .padding(.top, isWebSocket ? AtlantisSyntaxTheme.contentPaddingTopWebSocket : AtlantisSyntaxTheme.contentPaddingTopStandard)
        .padding(.horizontal, AtlantisSyntaxTheme.contentPaddingHorizontal)
        .padding(.bottom, AtlantisSyntaxTheme.contentPaddingBottom)
    }

    // MARK: - Footer button (§C6)

    private func footerButton(action: AtlantisOverviewFooterAction) -> some View {
        Button {
            switch action {
            case .copyCurl:
                AtlantisPasteboard.copy(package.curlCommand())
            }
        } label: {
            Text("Copy cURL")
                .font(Font(AtlantisSyntaxTheme.footerButtonFont))
                .foregroundColor(Color(AtlantisSyntaxTheme.accent))
                .frame(maxWidth: .infinity)
                .frame(height: AtlantisSyntaxTheme.footerButtonHeight)
                .background(Color(AtlantisSyntaxTheme.accentFill))
                .cornerRadius(AtlantisSyntaxTheme.footerButtonCornerRadius)
        }
        .buttonStyle(.plain)
    }
}

/// Pasteboard shim so views never touch platform types directly.
enum AtlantisPasteboard {
    static func copy(_ string: String) {
        #if os(iOS) || targetEnvironment(macCatalyst)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
#endif

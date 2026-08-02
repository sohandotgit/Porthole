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

private let atlantisDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

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

private struct AtlantisHeadersDetailView: View {
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

private struct AtlantisOverviewRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct AtlantisMessageDetailView: View {
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

private struct AtlantisMessageRowView: View {
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

/// Detail view for a single `TrafficPackage` — overview, headers, content-type-aware
/// bodies, copy/share actions, and (for WS/SSE) the message list.
public struct AtlantisTrafficDetailView: View {

    private let package: TrafficPackage

    @State private var showsShareSheet = false
    @State private var shareItems: [Any] = []

    public init(package: TrafficPackage) {
        self.package = package
    }

    private var hasError: Bool { package.error != nil }

    private var statusText: String {
        guard let statusCode = package.response?.statusCode else { return "—" }
        let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return "\(statusCode) \(reason)"
    }

    private var durationText: String {
        guard let endAt = package.endAt else { return "in-flight" }
        let seconds = endAt - package.startAt
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }

    private var responseContentType: String? {
        package.response.map { atlantisContentType(from: $0.headers) } ?? nil
    }

    private var isWebSocketOrSSE: Bool {
        package.packageType == .websocket || package.response?.isServerSentEventStream == true
    }

    public var body: some View {
        List {
            Section("Overview") {
                AtlantisOverviewRow(label: "Method",
                                    value: package.request.method,
                                    valueColor: AtlantisPalette.methodColor(package.request.method))
                AtlantisOverviewRow(label: "URL", value: package.request.url)
                AtlantisOverviewRow(label: "Status", value: statusText)
                if let error = package.error {
                    AtlantisOverviewRow(label: "Error",
                                        value: "\(error.code) · \(error.message)",
                                        valueColor: .red)
                }
                AtlantisOverviewRow(label: "Duration", value: durationText)
                AtlantisOverviewRow(label: "Content-Type", value: responseContentType ?? "—")
                AtlantisOverviewRow(label: "Started",
                                    value: atlantisDateTimeFormatter.string(from: Date(timeIntervalSince1970: package.startAt)))
            }

            Section("Details") {
                NavigationLink {
                    AtlantisHeadersDetailView(title: "Request Headers", headers: package.request.headers)
                } label: {
                    HStack {
                        Text("Request Headers")
                        Spacer()
                        Text("\(package.request.headers.count)")
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    AtlantisHeadersDetailView(title: "Response Headers", headers: package.response?.headers ?? [])
                } label: {
                    HStack {
                        Text("Response Headers")
                        Spacer()
                        Text("\(package.response?.headers.count ?? 0)")
                            .foregroundColor(.secondary)
                    }
                }
                AtlantisBodyPreviewCard(title: "Request Body",
                                        data: package.request.body ?? Data(),
                                        contentType: atlantisContentType(from: package.request.headers),
                                        method: package.request.method,
                                        side: .request,
                                        statusCode: nil)
                AtlantisBodyPreviewCard(title: "Response Body",
                                        data: package.responseBodyData,
                                        contentType: responseContentType,
                                        method: package.request.method,
                                        side: .response,
                                        statusCode: package.response?.statusCode)
            }

            if isWebSocketOrSSE {
                Section("Messages") {
                    ForEach(Array(package.websocketMessages.enumerated()), id: \.offset) { _, message in
                        AtlantisMessageRowView(message: message)
                    }
                }
            }
        }
        .navigationTitle("Detail")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Copy cURL") {
                        AtlantisPasteboard.copy(package.curlCommand())
                    }
                    if let requestBody = package.requestBodyForCopy() {
                        Button("Copy Request Body") {
                            AtlantisPasteboard.copy(requestBody)
                        }
                    }
                    if let responseBody = package.responseBodyForCopy() {
                        Button("Copy Response Body") {
                            AtlantisPasteboard.copy(responseBody)
                        }
                    }
                    #if os(iOS) || targetEnvironment(macCatalyst)
                    Button("Share cURL") {
                        shareItems = [package.curlCommand()]
                        showsShareSheet = true
                    }
                    #endif
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        #if os(iOS) || targetEnvironment(macCatalyst)
        .sheet(isPresented: $showsShareSheet) {
            AtlantisShareSheet(activityItems: shareItems)
        }
        #endif
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

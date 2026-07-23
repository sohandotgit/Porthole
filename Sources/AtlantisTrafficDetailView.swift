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

private enum AtlantisBodyKind: Sendable {
    case none
    case json(String)
    case image(Data)
    case text(String)
    case binary(Data)
}

private func atlantisBodyKind(_ data: Data, contentType: String?) -> AtlantisBodyKind {
    guard !data.isEmpty else { return .none }
    let ct = contentType?.lowercased() ?? ""

    if data.count < 5 * 1024 * 1024,
       let jsonObject = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
       let prettyString = String(data: pretty, encoding: .utf8) {
        return .json(prettyString)
    }

    if ct.hasPrefix("image/") || atlantisIsImageData(data) {
        return .image(data)
    }

    if ct.hasPrefix("text/") || ct == "application/xml" || ct == "application/x-www-form-urlencoded",
       let text = String(data: data, encoding: .utf8) {
        return .text(text)
    }

    if let text = String(data: data, encoding: .utf8) {
        return .text(text)
    }

    return .binary(data)
}

private func atlantisIsImageData(_ data: Data) -> Bool {
    #if os(iOS) || targetEnvironment(macCatalyst)
    return UIImage(data: data) != nil
    #elseif os(macOS)
    return NSImage(data: data) != nil
    #else
    return false
    #endif
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
@available(iOS 15.0, macOS 12.0, *)
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

private let atlantisLargeBodyThreshold = 256 * 1024  // UX defer only; render path is safe at any size

@available(iOS 15.0, macOS 12.0, *)
private struct AtlantisBodySectionView: View {
    let title: String
    let data: Data
    let contentType: String?
    @Binding var query: String

    @State private var kind: AtlantisBodyKind = .none
    @State private var revealed = false

    // text pulled from cached kind — no reparse
    private var bodyText: String? {
        switch kind {
        case .json(let t), .text(let t): return t
        default: return nil
        }
    }

    private var matchCount: Int {
        guard let t = bodyText else { return 0 }
        return AtlantisBodySearch.matchCount(in: t, query: query)
    }

    var body: some View {
        Section(query.isEmpty ? title : "\(title) (\(matchCount))") {
            if data.isEmpty {
                Text("No body")
                    .foregroundColor(.secondary)
            } else if data.count > atlantisLargeBodyThreshold && !revealed {
                Button("Show body (\(atlantisHumanBytes(data.count)))") {
                    revealed = true
                }
            } else {
                bodyContent
            }
        }
        // classify once, off main; recompute only if data identity changes
        .task(id: data) {
            let computed = await Task.detached(priority: .userInitiated) {
                atlantisBodyKind(data, contentType: contentType)
            }.value
            kind = computed
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch kind {
        case .none:
            Text("No body")
                .foregroundColor(.secondary)
        case .json(let pretty):
            AtlantisSelectableText(attributed: atlantisHighlighted(pretty, query: query))
        case .text(let text):
            AtlantisSelectableText(attributed: atlantisHighlighted(text, query: query))
        case .image(let imageData):
            atlantisImageView(imageData)
        case .binary(let binaryData):
            VStack(alignment: .leading, spacing: 4) {
                Text("⟨binary, \(binaryData.count) bytes⟩")
                    .foregroundColor(.secondary)
                DisclosureGroup("Hex preview") {
                    Text(binaryData.prefix(256).map { String(format: "%02x", $0) }.joined(separator: " "))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func atlantisImageView(_ data: Data) -> some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        if let uiImage = UIImage(data: data) {
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                Text("\(Int(uiImage.size.width))×\(Int(uiImage.size.height)) · \(atlantisHumanBytes(data.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height)) · \(atlantisHumanBytes(data.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        #endif
    }
}

@available(iOS 15.0, macOS 12.0, *)
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

@available(iOS 15.0, macOS 12.0, *)
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

@available(iOS 15.0, macOS 12.0, *)
private struct AtlantisBodyDetailView: View {
    let title: String
    let data: Data
    let contentType: String?

    @State private var query: String = ""

    var body: some View {
        List {
            AtlantisBodySectionView(title: title, data: data, contentType: contentType, query: $query)
        }
        .searchable(text: $query)
        .navigationTitle(title)
    }
}

@available(iOS 15.0, macOS 12.0, *)
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

@available(iOS 15.0, macOS 12.0, *)
private struct AtlantisMessageDetailView: View {
    let message: WebsocketMessagePackage

    @State private var query: String = ""

    private var data: Data {
        if let string = message.stringValue {
            return Data(string.utf8)
        }
        return message.dataValue ?? Data()
    }

    var body: some View {
        List {
            AtlantisBodySectionView(title: "Content", data: data, contentType: nil, query: $query)
        }
        .searchable(text: $query)
        .navigationTitle("Message")
    }
}

@available(iOS 15.0, macOS 12.0, *)
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
@available(iOS 15.0, macOS 12.0, *)
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
                NavigationLink {
                    AtlantisBodyDetailView(title: "Request Body",
                                           data: package.request.body ?? Data(),
                                           contentType: atlantisContentType(from: package.request.headers))
                } label: {
                    HStack {
                        Text("Request Body")
                        Spacer()
                        Text(atlantisHumanBytes(package.request.body?.count ?? 0))
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    AtlantisBodyDetailView(title: "Response Body",
                                           data: package.responseBodyData,
                                           contentType: responseContentType)
                } label: {
                    HStack {
                        Text("Response Body")
                        Spacer()
                        Text(atlantisHumanBytes(package.responseBodyData.count))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if isWebSocketOrSSE {
                Section("Messages") {
                    ForEach(Array(package.websocketMessages.enumerated()), id: \.offset) { _, message in
                        AtlantisMessageRowView(message: message)
                    }
                }
            }
        }
        .navigationTitle("Request")
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

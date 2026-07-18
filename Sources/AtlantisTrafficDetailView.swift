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

private enum AtlantisBodyKind {
    case none
    case json(String)
    case image(Data)
    case text(String)
    case binary(Data)
}

private func atlantisBodyKind(_ data: Data, contentType: String?) -> AtlantisBodyKind {
    guard !data.isEmpty else { return .none }
    let ct = contentType?.lowercased() ?? ""

    if let jsonObject = try? JSONSerialization.jsonObject(with: data),
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

private let atlantisLargeBodyThreshold = 512 * 1024

@available(iOS 15.0, macOS 12.0, *)
private struct AtlantisBodySectionView: View {
    let title: String
    let data: Data
    let contentType: String?

    @State private var query: String = ""
    @State private var revealed = false

    private var matchCount: Int {
        if case .text(let text) = atlantisBodyKind(data, contentType: contentType) {
            return AtlantisBodySearch.matchCount(in: text, query: query)
        }
        if case .json(let text) = atlantisBodyKind(data, contentType: contentType) {
            return AtlantisBodySearch.matchCount(in: text, query: query)
        }
        return 0
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
                if isSearchable {
                    TextField("Search \(title)", text: $query)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var isSearchable: Bool {
        switch atlantisBodyKind(data, contentType: contentType) {
        case .json, .text: return true
        default: return false
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch atlantisBodyKind(data, contentType: contentType) {
        case .none:
            Text("No body")
                .foregroundColor(.secondary)
        case .json(let pretty):
            ScrollView(.horizontal) {
                Text(atlantisHighlighted(pretty, query: query))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .text(let text):
            ScrollView(.horizontal) {
                Text(atlantisHighlighted(text, query: query))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
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

    @State private var query: String = ""

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
                    HStack(alignment: .top) {
                        Text(atlantisHighlighted(header.key, query: query))
                            .fontWeight(.semibold)
                        Text(atlantisHighlighted(header.value, query: query))
                            .textSelection(.enabled)
                    }
                }
                TextField("Search \(title)", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
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
            AtlantisBodySectionView(title: "Content", data: data, contentType: nil)
        }
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
                HStack {
                    Text("Method")
                    Spacer()
                    Text(package.request.method)
                        .foregroundColor(AtlantisPalette.methodColor(package.request.method))
                }
                HStack {
                    Text("URL")
                    Spacer()
                    Text(package.request.url)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                }
                if let error = package.error {
                    HStack {
                        Text("Error")
                        Spacer()
                        Text("\(error.code) · \(error.message)")
                            .foregroundColor(.red)
                    }
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(durationText)
                }
                HStack {
                    Text("Request size")
                    Spacer()
                    Text(atlantisHumanBytes(package.request.body?.count ?? 0))
                }
                HStack {
                    Text("Response size")
                    Spacer()
                    Text(atlantisHumanBytes(package.responseBodyData.count))
                }
                HStack {
                    Text("Content-Type")
                    Spacer()
                    Text(responseContentType ?? "—")
                }
                HStack {
                    Text("Started")
                    Spacer()
                    Text(atlantisDateTimeFormatter.string(from: Date(timeIntervalSince1970: package.startAt)))
                }
            }

            AtlantisHeadersSectionView(title: "Request Headers", headers: package.request.headers)
            AtlantisHeadersSectionView(title: "Response Headers", headers: package.response?.headers ?? [])

            AtlantisBodySectionView(title: "Request Body",
                                    data: package.request.body ?? Data(),
                                    contentType: atlantisContentType(from: package.request.headers))
            AtlantisBodySectionView(title: "Response Body",
                                    data: package.responseBodyData,
                                    contentType: responseContentType)

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

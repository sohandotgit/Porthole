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

private struct AtlantisJSONToken {
    let range: Range<String.Index>
    let color: Color
}

/// Single-pass, best-effort JSON tokenizer over already-pretty-printed text — not a
/// validating parser. Classifies quoted strings (as keys when followed by `:`, else
/// values), numbers, and `true`/`false`/`null` literals; everything else (punctuation,
/// whitespace) is left uncolored.
private func atlantisJSONTokens(in text: String) -> [AtlantisJSONToken] {
    var tokens: [AtlantisJSONToken] = []
    var i = text.startIndex
    let end = text.endIndex

    func nextNonWhitespace(from idx: String.Index) -> Character? {
        var j = idx
        while j < end, text[j].isWhitespace { j = text.index(after: j) }
        return j < end ? text[j] : nil
    }

    while i < end {
        let c = text[i]
        if c == "\"" {
            let start = i
            var j = text.index(after: i)
            var closed = false
            while j < end {
                if text[j] == "\\" {
                    j = text.index(after: j)
                    if j < end { j = text.index(after: j) }
                    continue
                }
                if text[j] == "\"" { j = text.index(after: j); closed = true; break }
                j = text.index(after: j)
            }
            let isKey = closed && nextNonWhitespace(from: j) == ":"
            tokens.append(AtlantisJSONToken(range: start..<j,
                                             color: isKey ? .blue : Color(red: 0.75, green: 0.15, blue: 0.15)))
            i = j
        } else if c == "-" || c.isNumber {
            let start = i
            var j = text.index(after: i)
            while j < end {
                let ch = text[j]
                guard ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" || ch == "-" else { break }
                j = text.index(after: j)
            }
            tokens.append(AtlantisJSONToken(range: start..<j, color: .purple))
            i = j
        } else if c == "t" || c == "f" || c == "n" {
            let matched: String?
            if text[i...].hasPrefix("true") { matched = "true" }
            else if text[i...].hasPrefix("false") { matched = "false" }
            else if text[i...].hasPrefix("null") { matched = "null" }
            else { matched = nil }

            if let word = matched {
                let j = text.index(i, offsetBy: word.count)
                tokens.append(AtlantisJSONToken(range: i..<j, color: .orange))
                i = j
            } else {
                i = text.index(after: i)
            }
        } else {
            i = text.index(after: i)
        }
    }
    return tokens
}

/// Colors JSON tokens (keys, string values, numbers, literals) in pretty-printed JSON text.
@available(iOS 15.0, macOS 12.0, *)
private func atlantisJSONSyntaxColored(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    for token in atlantisJSONTokens(in: text) {
        guard let range = Range(token.range, in: attributed) else { continue }
        attributed[range].foregroundColor = token.color
    }
    return attributed
}

/// Overlays search-match backgrounds on top of an already-colored base string.
/// The match at `currentIndex` gets a distinct color so next/prev navigation is visible.
@available(iOS 15.0, macOS 12.0, *)
private func atlantisApplySearchHighlight(_ base: AttributedString, in text: String,
                                           ranges: [Range<String.Index>], currentIndex: Int) -> AttributedString {
    guard !ranges.isEmpty else { return base }
    var attributed = base
    for (index, range) in ranges.enumerated() {
        guard let attributedRange = Range(range, in: attributed) else { continue }
        attributed[attributedRange].backgroundColor = index == currentIndex ? .orange : .yellow
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
    var chromeless: Bool = false

    @State private var kind: AtlantisBodyKind = .none
    @State private var revealed = false
    @State private var wordWrap = true

    // syntax-colored, no search overlay — rebuilt only when data/kind changes
    @State private var baseAttributed: AttributedString = AttributedString("")
    // baseAttributed + search-match backgrounds — what's actually rendered
    @State private var highlighted: AttributedString = AttributedString("")
    @State private var matchRanges: [Range<String.Index>] = []
    @State private var currentMatchIndex: Int = 0
    // bumped whenever the current match should be scrolled into view
    @State private var scrollTrigger: Int = 0

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

    private var currentScrollNSRange: NSRange? {
        guard let t = bodyText, matchRanges.indices.contains(currentMatchIndex) else { return nil }
        return NSRange(matchRanges[currentMatchIndex], in: t)
    }

    // rebuilds JSON syntax coloring — only needed when the body itself changes
    private func recomputeBase() {
        guard let t = bodyText else { baseAttributed = AttributedString(""); return }
        if case .json = kind {
            baseAttributed = atlantisJSONSyntaxColored(t)
        } else {
            baseAttributed = AttributedString(t)
        }
    }

    // reapplies search highlight on top of the cached base — cheap, safe on every query edit
    private func recomputeSearch() {
        guard let t = bodyText else {
            matchRanges = []
            currentMatchIndex = 0
            highlighted = baseAttributed
            return
        }
        matchRanges = query.isEmpty ? [] : AtlantisBodySearch.matchRanges(in: t, query: query)
        currentMatchIndex = 0
        highlighted = atlantisApplySearchHighlight(baseAttributed, in: t, ranges: matchRanges, currentIndex: currentMatchIndex)
        scrollTrigger += 1
    }

    private func advanceMatch(by delta: Int) {
        guard !matchRanges.isEmpty, let t = bodyText else { return }
        currentMatchIndex = (currentMatchIndex + delta + matchRanges.count) % matchRanges.count
        highlighted = atlantisApplySearchHighlight(baseAttributed, in: t, ranges: matchRanges, currentIndex: currentMatchIndex)
        scrollTrigger += 1
    }

    private func copyBody() {
        guard let t = bodyText else { return }
        AtlantisPasteboard.copy(t)
    }

    var body: some View {
        Group {
            if chromeless {
                VStack(alignment: .leading, spacing: 6) {
                    Text(query.isEmpty ? title : "\(title) (\(matchCount))")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    if bodyText != nil { toolbarRow }
                    sectionBody
                }
            } else {
                Section(query.isEmpty ? title : "\(title) (\(matchCount))") {
                    if bodyText != nil { toolbarRow }
                    sectionBody
                }
            }
        }
        // classify once, off main; recompute only if data identity changes
        .task(id: data) {
            let computed = await Task.detached(priority: .userInitiated) {
                atlantisBodyKind(data, contentType: contentType)
            }.value
            kind = computed
            recomputeBase()
            recomputeSearch()
        }
        .onChange(of: query) { _ in recomputeSearch() }
    }

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: 16) {
            if !query.isEmpty {
                if matchRanges.isEmpty {
                    Text("No matches")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(currentMatchIndex + 1)/\(matchRanges.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button { advanceMatch(by: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    Button { advanceMatch(by: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
            Spacer()
            Button { wordWrap.toggle() } label: {
                Image(systemName: wordWrap ? "arrow.left.and.right.square" : "text.alignleft")
            }
            .help(wordWrap ? "Disable word wrap" : "Enable word wrap")
            Button(action: copyBody) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy body")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var sectionBody: some View {
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

    @ViewBuilder
    private var bodyContent: some View {
        switch kind {
        case .none:
            Text("No body")
                .foregroundColor(.secondary)
        case .json, .text:
            AtlantisSelectableText(attributed: highlighted, wordWrap: wordWrap,
                                    scrollToRange: currentScrollNSRange, scrollToken: scrollTrigger)
                .frame(minHeight: 120, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            AtlantisBodySectionView(title: title, data: data, contentType: contentType, query: $query, chromeless: true)
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
        VStack(alignment: .leading, spacing: 0) {
            AtlantisBodySectionView(title: "Content", data: data, contentType: nil, query: $query, chromeless: true)
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

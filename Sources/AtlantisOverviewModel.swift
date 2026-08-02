//
//  AtlantisOverviewModel.swift
//  atlantis
//
//  Headless presentation model for the Request Overview screen
//  (design/request-overview-ui.md, design/request-overview-tokens.md,
//  Tests/request-overview.spec.md). No SwiftUI import — unit-testable without a view.
//

import Foundation

/// Status family for the Request Overview band. Precedence (first match wins):
/// websocket, pending, transportError, clientError, serverError, success.
enum AtlantisStatusFamily: Equatable {
    case success
    case clientError
    case serverError
    case transportError
    case pending
    case websocket

    /// Status-only classification with no package (no `.pending`, no `.websocket`) —
    /// used by the `AtlantisPalette` shim in `AtlantisTrafficListView.swift`.
    init(statusCode: Int?, hasError: Bool) {
        if hasError {
            self = .transportError
            return
        }
        guard let code = statusCode else {
            self = .success
            return
        }
        if (400..<500).contains(code) {
            self = .clientError
        } else if (500..<600).contains(code) {
            self = .serverError
        } else {
            self = .success
        }
    }
}

enum AtlantisOverviewFooterAction: Equatable {
    case copyCurl
}

struct AtlantisOverviewDetailRow: Equatable {
    enum Accessory: Equatable {
        case count(Int)
        case word(String)
        case badge(String, String)
    }

    enum IconKind: Equatable {
        case accent
        case success
        case neutral
    }

    let title: String
    let accessory: Accessory
    let isTappable: Bool
    let iconKind: IconKind
}

struct AtlantisOverviewStatTile: Equatable {
    enum Content: Equatable {
        case value(String, detail: String?, iconKind: AtlantisOverviewDetailRow.IconKind)
        case badge(String, String, detail: String?, iconKind: AtlantisOverviewDetailRow.IconKind)
        case dimmed(String)
        case skeleton(label: String)
    }

    let title: String
    let content: Content
    let isLive: Bool
}

struct AtlantisSparklineBucket: Equatable {
    enum Direction: Equatable {
        case received
        case sent
        case none
    }

    let count: Int
    let direction: Direction
    let heightFraction: Double
}

struct AtlantisOverviewMessagePreview: Equatable {
    let chipLabel: String
    let timestampText: String
    let sizeText: String
    let bodyPreview: String
    let messageType: WebsocketMessagePackage.MessageType
}

/// Presentation model for `AtlantisTrafficDetailView`'s Request Overview screen.
/// Every time-dependent value takes an explicit `now` — never reads the wall clock.
struct AtlantisOverviewModel {

    let package: TrafficPackage
    let now: TimeInterval
    let family: AtlantisStatusFamily

    init(package: TrafficPackage, now: TimeInterval) {
        self.package = package
        self.now = now
        self.family = Self.classify(package)
    }

    // MARK: - Classification (UI doc §2)

    private static func classify(_ package: TrafficPackage) -> AtlantisStatusFamily {
        if package.packageType == .websocket { return .websocket }
        if package.endAt == nil { return .pending }
        if package.error != nil { return .transportError }
        if let code = package.response?.statusCode {
            if (400..<500).contains(code) { return .clientError }
            if (500..<600).contains(code) { return .serverError }
        }
        return .success
    }

    // MARK: - Caption / method / nav title / footer

    var caption: String {
        switch family {
        case .success: return "SUCCESS"
        case .clientError: return "CLIENT ERROR"
        case .serverError: return "SERVER ERROR"
        case .transportError: return "TRANSPORT ERROR"
        case .pending: return "IN FLIGHT"
        case .websocket: return "101 SWITCHING PROTOCOLS"
        }
    }

    var methodBadge: String {
        if package.packageType == .websocket {
            let scheme = URLComponents(string: package.request.url)?.scheme?.lowercased()
            return scheme == "wss" ? "WSS" : "WS"
        }
        return package.request.method.uppercased()
    }

    var navigationTitle: String {
        family == .websocket ? "Socket" : "Request"
    }

    /// UI doc §9.1 — `true` (toolbar chrome forced dark) for `.websocket`, `false`
    /// (inherit) otherwise. Bool, not `ColorScheme`, to keep this file SwiftUI-free.
    var bandChromeIsDark: Bool {
        family == .websocket
    }

    var footerAction: AtlantisOverviewFooterAction? {
        switch family {
        case .pending, .websocket: return nil
        default: return .copyCurl
        }
    }

    // MARK: - Status block (UI doc §2, §3.4)

    private static let reasonWords: [Int: String] = [
        200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 206: "Partial",
        301: "Moved", 302: "Found", 304: "Not Modified", 307: "Temporary", 308: "Permanent",
        400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
        405: "Not Allowed", 409: "Conflict", 410: "Gone", 422: "Unprocessable", 429: "Too Many",
        500: "Server Error", 502: "Bad Gateway", 503: "Unavailable", 504: "Timeout"
    ]

    private static func reasonFallback(for code: Int) -> String {
        switch code {
        case 100..<200: return "Informational"
        case 200..<300: return "Success"
        case 300..<400: return "Redirect"
        case 400..<500: return "Client Error"
        case 500..<600: return "Server Error"
        default: return "Status"
        }
    }

    private static func reasonWord(for code: Int) -> String {
        reasonWords[code] ?? reasonFallback(for: code)
    }

    var statusNumeral: String? {
        switch family {
        case .success, .clientError, .serverError:
            guard let code = package.response?.statusCode else { return "\u{2014}" }
            return "\(code)"
        case .transportError:
            guard let error = package.error else { return nil }
            return "\(error.code)"
        default:
            return nil
        }
    }

    var reasonWord: String? {
        switch family {
        case .success, .clientError, .serverError:
            guard let code = package.response?.statusCode else { return nil }
            return Self.reasonWord(for: code)
        default:
            return nil
        }
    }

    var statusWord: String? {
        switch family {
        case .transportError: return "Failed"
        case .pending: return "In flight"
        case .websocket: return isConnected ? "Connected" : "Closed"
        default: return nil
        }
    }

    // MARK: - Duration value / sub-line (UI doc §3.5)

    var durationValue: String {
        switch family {
        case .pending:
            return AtlantisFormat.elapsed(startAt: package.startAt, now: now)
        case .websocket:
            let end = package.endAt ?? now
            return AtlantisFormat.uptime(end - package.startAt)
        default:
            return AtlantisFormat.duration(startAt: package.startAt, endAt: package.endAt)
        }
    }

    var subLine: String {
        switch family {
        case .transportError:
            return "no response"
        case .pending:
            return "elapsed"
        case .websocket:
            switch websocketMessages.count {
            case 0: return "no frames"
            case 1: return "1 frame"
            default: return "\(websocketMessages.count) frames"
            }
        default:
            return AtlantisFormat.bytes(package.responseBodyData.count)
        }
    }

    // MARK: - Path / host / error card (UI doc §3.6, §3.7)

    var pathText: String { AtlantisPathHost(url: package.request.url).primary }
    var hostText: String { AtlantisPathHost(url: package.request.url).host }

    var errorHeadline: String? {
        guard family == .transportError, let error = package.error else { return nil }
        return error.message
    }

    var errorCodeLine: String? {
        guard family == .transportError, let error = package.error else { return nil }
        return "Error \(error.code)"
    }

    // MARK: - Timing card (UI doc §5)

    var timingTitle: String {
        switch family {
        case .pending: return "Timing \u{00B7} live"
        case .websocket: return isConnected ? "Timing \u{00B7} live" : "Timing"
        default: return "Timing"
        }
    }

    var timingAccessory: String? {
        switch family {
        case .pending: return "running"
        case .websocket: return isConnected ? "running" : nil
        default: return nil
        }
    }

    var timingSecondRowLabel: String {
        switch family {
        case .pending: return "Elapsed"
        case .websocket: return isConnected ? "Elapsed" : "Duration"
        default: return "Duration"
        }
    }

    var startedText: String {
        AtlantisFormat.started(package.startAt, now: now, timeZone: .current)
    }

    // MARK: - Details card (UI doc §6)

    private static func badgeLabel(kind: AtlantisBodyClassifiedKind, contentType: String?, headers: [Header]) -> String {
        guard kind == .binary else { return kind.badge }
        let encoding = headers.first { $0.key.caseInsensitiveCompare("Content-Encoding") == .orderedSame }?.value ?? ""
        let signal = ((contentType ?? "") + " " + encoding).lowercased()
        if signal.contains("gzip") { return "GZIP" }
        if signal.contains("pdf") { return "PDF" }
        return kind.badge
    }

    var detailRows: [AtlantisOverviewDetailRow] {
        let reqHeaders = package.request.headers
        let respHeaders = package.response?.headers ?? []

        let reqCT = AtlantisBodyClassifier.contentType(from: reqHeaders)
        let reqClass = AtlantisBodyClassifier.classify(package.request.body ?? Data(), contentType: reqCT)
        let respCT = AtlantisBodyClassifier.contentType(from: respHeaders)
        let respClass = AtlantisBodyClassifier.classify(package.responseBodyData, contentType: respCT)

        let reqBodyRow: AtlantisOverviewDetailRow
        if reqClass.kind == .empty {
            reqBodyRow = AtlantisOverviewDetailRow(title: "Request Body", accessory: .word("No body"), isTappable: false, iconKind: .neutral)
        } else {
            let badge = Self.badgeLabel(kind: reqClass.kind, contentType: reqCT, headers: reqHeaders)
            reqBodyRow = AtlantisOverviewDetailRow(title: "Request Body", accessory: .badge(badge, AtlantisFormat.bytes(reqClass.byteCount)), isTappable: true, iconKind: .accent)
        }

        let respBodyRow: AtlantisOverviewDetailRow
        if respClass.kind == .empty {
            respBodyRow = AtlantisOverviewDetailRow(title: "Response Body", accessory: .word("No body"), isTappable: false, iconKind: .neutral)
        } else {
            let badge = Self.badgeLabel(kind: respClass.kind, contentType: respCT, headers: respHeaders)
            respBodyRow = AtlantisOverviewDetailRow(title: "Response Body", accessory: .badge(badge, AtlantisFormat.bytes(respClass.byteCount)), isTappable: true, iconKind: .success)
        }

        return [
            AtlantisOverviewDetailRow(title: "Request Headers", accessory: .count(reqHeaders.count), isTappable: !reqHeaders.isEmpty, iconKind: .accent),
            AtlantisOverviewDetailRow(title: "Response Headers", accessory: .count(respHeaders.count), isTappable: !respHeaders.isEmpty, iconKind: .accent),
            reqBodyRow,
            respBodyRow
        ]
    }

    // MARK: - Stat-tile grids (UI doc §7)

    func statTiles(for family: AtlantisStatusFamily) -> [AtlantisOverviewStatTile] {
        switch family {
        case .transportError: return transportErrorStatTiles
        case .pending: return pendingStatTiles
        default: return []
        }
    }

    private var transportErrorStatTiles: [AtlantisOverviewStatTile] {
        let reqHeaders = package.request.headers
        let detail = reqHeaders.first.map { "\($0.key): \($0.value)" }
        let tile1 = AtlantisOverviewStatTile(
            title: "Req Headers",
            content: .value("\(reqHeaders.count)", detail: detail, iconKind: .accent),
            isLive: true
        )
        let tile2 = AtlantisOverviewStatTile(title: "Res Headers", content: .dimmed("Never received"), isLive: false)

        let reqCT = AtlantisBodyClassifier.contentType(from: reqHeaders)
        let reqClass = AtlantisBodyClassifier.classify(package.request.body ?? Data(), contentType: reqCT)
        let tile3: AtlantisOverviewStatTile
        if reqClass.kind == .empty {
            tile3 = AtlantisOverviewStatTile(title: "Request Body", content: .dimmed("Nothing sent"), isLive: false)
        } else {
            let badge = Self.badgeLabel(kind: reqClass.kind, contentType: reqCT, headers: reqHeaders)
            tile3 = AtlantisOverviewStatTile(
                title: "Request Body",
                content: .badge(badge, AtlantisFormat.bytes(reqClass.byteCount), detail: nil, iconKind: .accent),
                isLive: true
            )
        }
        let tile4 = AtlantisOverviewStatTile(title: "Response Body", content: .dimmed("Nothing received"), isLive: false)
        return [tile1, tile2, tile3, tile4]
    }

    private var pendingStatTiles: [AtlantisOverviewStatTile] {
        let reqHeaders = package.request.headers
        let detail = reqHeaders.first.map { "\($0.key): \($0.value)" }
        let tile1 = AtlantisOverviewStatTile(
            title: "Req Headers",
            content: .value("\(reqHeaders.count)", detail: detail, iconKind: .accent),
            isLive: true
        )

        let reqCT = AtlantisBodyClassifier.contentType(from: reqHeaders)
        let reqClass = AtlantisBodyClassifier.classify(package.request.body ?? Data(), contentType: reqCT)
        let tile2: AtlantisOverviewStatTile
        if reqClass.kind == .empty {
            tile2 = AtlantisOverviewStatTile(title: "Request Body", content: .dimmed("Nothing sent"), isLive: false)
        } else {
            let badge = Self.badgeLabel(kind: reqClass.kind, contentType: reqCT, headers: reqHeaders)
            tile2 = AtlantisOverviewStatTile(
                title: "Request Body",
                content: .badge(badge, AtlantisFormat.bytes(reqClass.byteCount), detail: "sending\u{2026}", iconKind: .accent),
                isLive: true
            )
        }
        let tile3 = AtlantisOverviewStatTile(title: "Response", content: .skeleton(label: "Waiting for headers\u{2026}"), isLive: false)
        return [tile1, tile2, tile3]
    }

    // MARK: - WebSocket folds (UI doc §8, spec §3)

    var websocketMessages: [WebsocketMessagePackage] { package.websocketMessages }

    private static func byteCount(of message: WebsocketMessagePackage) -> Int {
        if let data = message.dataValue { return data.count }
        if let string = message.stringValue { return string.utf8.count }
        return 0
    }

    var receivedCount: Int { websocketMessages.filter { $0.messageType == .receive }.count }
    var sentCount: Int { websocketMessages.filter { $0.messageType == .send }.count }
    var frameCount: Int { websocketMessages.count }

    var receivedBytes: Int {
        websocketMessages.filter { $0.messageType == .receive }.reduce(0) { $0 + Self.byteCount(of: $1) }
    }

    var sentBytes: Int {
        websocketMessages.filter { $0.messageType == .send }.reduce(0) { $0 + Self.byteCount(of: $1) }
    }

    var receivedBytesText: String { AtlantisFormat.bytes(receivedBytes) }
    var sentBytesText: String { AtlantisFormat.bytes(sentBytes) }

    var rateText: String {
        let count = websocketMessages.filter { $0.createdAt > now - 60 }.count
        return String(format: "%.1f/s", Double(count) / 60.0)
    }

    var isConnected: Bool {
        package.endAt == nil && websocketMessages.last?.messageType != .sendCloseMessage
    }

    var isLive: Bool {
        switch family {
        case .pending: return true
        case .websocket: return isConnected
        default: return false
        }
    }

    func elapsedText(now: TimeInterval) -> String {
        AtlantisFormat.elapsed(startAt: package.startAt, now: now)
    }

    /// Single live-tick value, branched by family (B1/B2) — `.pending` ticks
    /// `elapsed` (`%.0f ms` / `%.2f s`), `.websocket` ticks `uptime` (`m:ss`).
    /// The band and the timing card both read this from one hoisted `TimelineView`.
    func liveValue(now: TimeInterval) -> String {
        switch family {
        case .pending:
            return elapsedText(now: now)
        case .websocket:
            return AtlantisFormat.uptime(now - package.startAt)
        default:
            return durationValue
        }
    }

    // MARK: - Sparkline (UI doc §8.2, spec §3.5)

    private var sparklineWindowSeconds: TimeInterval {
        let end = package.endAt ?? now
        return min(max(end - package.startAt, 0), AtlantisSyntaxTheme.sparkWindowSeconds)
    }

    var sparklineWindowLabel: String {
        let window = sparklineWindowSeconds
        if window >= AtlantisSyntaxTheme.sparkWindowSeconds {
            return "4 min"
        }
        return AtlantisFormat.uptime(window)
    }

    var sparkline: [AtlantisSparklineBucket] {
        let bucketCount = AtlantisSyntaxTheme.sparkBucketCount
        let window = sparklineWindowSeconds
        let end = package.endAt ?? now
        let start = end - window

        guard window > 0 else {
            return Array(repeating: AtlantisSparklineBucket(count: 0, direction: .none, heightFraction: AtlantisSyntaxTheme.sparkMinHeightFraction), count: bucketCount)
        }

        var counts = [Int](repeating: 0, count: bucketCount)
        var receiveCounts = [Int](repeating: 0, count: bucketCount)
        var sendCounts = [Int](repeating: 0, count: bucketCount)

        for message in websocketMessages {
            guard message.createdAt >= start, message.createdAt <= end else { continue }
            let rawIndex = Int(floor((message.createdAt - start) / window * Double(bucketCount)))
            let index = min(bucketCount - 1, max(0, rawIndex))
            counts[index] += 1
            switch message.messageType {
            case .receive: receiveCounts[index] += 1
            case .send: sendCounts[index] += 1
            case .pingPong, .sendCloseMessage: break
            }
        }

        let maxCount = counts.max() ?? 0
        return (0..<bucketCount).map { i in
            let count = counts[i]
            let direction: AtlantisSparklineBucket.Direction
            if count == 0 {
                direction = .none
            } else if sendCounts[i] > receiveCounts[i] {
                direction = .sent
            } else {
                direction = .received
            }
            let heightFraction = count == 0
                ? AtlantisSyntaxTheme.sparkMinHeightFraction
                : max(Double(count) / Double(maxCount), AtlantisSyntaxTheme.sparkMinHeightFraction)
            return AtlantisSparklineBucket(count: count, direction: direction, heightFraction: heightFraction)
        }
    }

    // MARK: - Message previews (UI doc §8.4, spec §3.6)

    var messagePreviews: [AtlantisOverviewMessagePreview] {
        let count = min(AtlantisSyntaxTheme.messagePreviewCount, websocketMessages.count)
        guard count > 0 else { return [] }
        return websocketMessages.suffix(count).reversed().map(Self.preview(for:))
    }

    var seeAllLabel: String? {
        websocketMessages.isEmpty ? nil : "See all \(websocketMessages.count)"
    }

    private static func chipLabel(for messageType: WebsocketMessagePackage.MessageType) -> String {
        switch messageType {
        case .receive: return "RECV"
        case .send: return "SENT"
        case .pingPong: return "PING"
        case .sendCloseMessage: return "CLOSE"
        }
    }

    private static func preview(for message: WebsocketMessagePackage) -> AtlantisOverviewMessagePreview {
        let bodyPreview: String
        if let string = message.stringValue {
            bodyPreview = string
        } else if let data = message.dataValue {
            bodyPreview = String(data: data, encoding: .utf8) ?? "\u{27E8}binary, \(data.count) bytes\u{27E9}"
        } else {
            bodyPreview = ""
        }
        return AtlantisOverviewMessagePreview(
            chipLabel: chipLabel(for: message.messageType),
            timestampText: AtlantisFormat.time(message.createdAt),
            sizeText: AtlantisFormat.bytes(byteCount(of: message)),
            bodyPreview: bodyPreview,
            messageType: message.messageType
        )
    }
}

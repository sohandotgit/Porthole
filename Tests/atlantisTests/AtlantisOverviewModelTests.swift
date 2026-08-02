import Foundation
import XCTest
@testable import Atlantis

// Fixture helpers per Tests/request-overview.spec.md §0.
//
// NOTE ON TIMESTAMPS: `WebsocketMessagePackage`'s public initializers
// (Sources/Packages.swift, read-only for this roadmap) always stamp `createdAt`
// from `Date()` — there is no seam to inject an arbitrary `createdAt`. The spec's
// `wsMessage(_:at:)` helper signature assumes one exists. Tests that only depend on
// message *type* and *insertion order* (counts, byte totals, chip labels, body
// previews, newest-first ordering, the connected/closed predicate) are unaffected
// and asserted exactly. Tests that need specific relative offsets from a `now`
// baseline (sparkline bucket-by-bucket placement, the 60s rate window) are reduced
// to structural/format-level checks instead of the spec's literal per-bucket values.
private func makePackage(id: String = UUID().uuidString,
                          method: String = "GET",
                          url: String = "https://api.example.com/users",
                          reqHeaders: [Header] = [],
                          reqBody: Data? = nil,
                          status: Int? = 200,
                          respHeaders: [Header] = [],
                          respBody: Data = Data(),
                          error: Error? = nil,
                          packageType: TrafficPackage.PackageType = .http,
                          startAt: TimeInterval = 1_000,
                          endAt: TimeInterval? = 1_000.5) -> TrafficPackage {
    let request = Request(url: url, method: method, headers: reqHeaders, body: reqBody)
    let response = status.map { Response(statusCode: $0, headers: respHeaders) }
    let package = TrafficPackage(id: id,
                                  request: request,
                                  response: response,
                                  responseBodyData: respBody,
                                  packageType: packageType,
                                  startAt: startAt,
                                  endAt: endAt)
    if let error = error {
        package.updateDidComplete(error)
    }
    return package
}

/// `TrafficPackage.updateDidComplete(_:)` unconditionally stamps `endAt = Date()`
/// whenever an error is set (Sources/Packages.swift:108-113, read-only) — there is
/// no mutator path that sets `error` while leaving `endAt` at a fixture value (or
/// nil). `TrafficPackage` is `Codable` with no custom `init(from:)`/`encode(to:)`,
/// so decoding a crafted JSON payload is the only read-only-compliant way to reach
/// states the public API can't construct (spec §1.3.4: error set, endAt nil; and
/// §2.4.3's exact 30s transport-error duration).
private func makeRawPackage(startAt: TimeInterval = 1_000,
                             endAt: TimeInterval? = nil,
                             status: Int? = nil,
                             errorCode: Int? = nil,
                             errorMessage: String = "err",
                             packageType: TrafficPackage.PackageType = .http,
                             url: String = "https://api.example.com/users") -> TrafficPackage {
    var json: [String: Any] = [
        "id": UUID().uuidString,
        "startAt": startAt,
        "request": ["url": url, "method": "GET", "headers": []],
        "responseBodyData": "",
        "packageType": packageType.rawValue,
        "websocketMessages": []
    ]
    if let endAt = endAt { json["endAt"] = endAt }
    if let status = status { json["response"] = ["statusCode": status, "headers": []] }
    if let errorCode = errorCode { json["error"] = ["code": errorCode, "message": errorMessage] }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(TrafficPackage.self, from: data)
}

/// Real (non-zero-filled) JSON bytes of an exact length — `classify()` only
/// recognizes `.json` for bytes that actually parse as JSON.
private func jsonBody(totalBytes: Int) -> Data {
    let prefix = "{\"pad\":\""
    let suffix = "\"}"
    let padLength = max(0, totalBytes - prefix.utf8.count - suffix.utf8.count)
    return Data((prefix + String(repeating: "x", count: padLength) + suffix).utf8)
}

/// Bytes that fail UTF-8 decoding, so `classify()` lands on `.binary` rather than
/// `.text` (an all-zero `Data(count:)` buffer decodes as valid — if unwanted — UTF-8).
private func binaryBody(count: Int) -> Data {
    Data(repeating: 0xFF, count: count)
}

private func wsMessage(_ type: WebsocketMessagePackage.MessageType,
                        string: String? = nil,
                        data: Data? = nil) -> WebsocketMessagePackage {
    if type == .sendCloseMessage {
        return WebsocketMessagePackage(id: UUID().uuidString, closeCode: 1000, reason: data)
    }
    let message: WebsocketMessagePackage.Message = string.map { .string($0) } ?? .data(data ?? Data())
    return WebsocketMessagePackage(id: UUID().uuidString, message: message, messageType: type)
}

private func wsPackage(startAt: TimeInterval = 0,
                        endAt: TimeInterval? = nil,
                        url: String = "wss://socket.example.com/realtime/v1/presence",
                        messages: [WebsocketMessagePackage] = []) -> TrafficPackage {
    let request = Request(url: url, method: "GET", headers: [], body: nil)
    let package = TrafficPackage(id: UUID().uuidString,
                                  request: request,
                                  response: nil,
                                  responseBodyData: Data(),
                                  packageType: .websocket,
                                  startAt: startAt,
                                  endAt: endAt)
    for message in messages {
        package.setWebsocketMessagePackage(package: message)
    }
    return package
}

private func model(_ package: TrafficPackage, now: TimeInterval) -> AtlantisOverviewModel {
    AtlantisOverviewModel(package: package, now: now)
}

private func family(_ p: TrafficPackage, now: TimeInterval = 2_000) -> AtlantisStatusFamily {
    model(p, now: now).family
}

// MARK: - §1 Classification

final class AtlantisStatusFamilyClassificationTests: XCTestCase {

    func testStatusCodeBoundaries() {
        let cases: [(Int?, AtlantisStatusFamily)] = [
            (100, .success), (199, .success), (200, .success), (299, .success),
            (300, .success), (399, .success), (400, .clientError), (499, .clientError),
            (500, .serverError), (599, .serverError), (600, .success), (0, .success)
        ]
        for (status, expected) in cases {
            let p = makePackage(status: status, error: nil, packageType: .http, startAt: 1_000, endAt: 1_000.5)
            XCTAssertEqual(family(p), expected, "status \(String(describing: status))")
        }
        let noResponse = makePackage(status: nil, error: nil, packageType: .http, startAt: 1_000, endAt: 1_000.5)
        XCTAssertEqual(family(noResponse), .success)
    }

    func testErrorBeatsStatus() {
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        XCTAssertEqual(family(makePackage(status: 200, error: err, endAt: 1_030)), .transportError)
        XCTAssertEqual(family(makePackage(status: 404, error: err, endAt: 1_030)), .transportError)
        XCTAssertEqual(family(makePackage(status: 503, error: err, endAt: 1_030)), .transportError)
        XCTAssertEqual(family(makePackage(status: nil, error: err, endAt: 1_030)), .transportError)
    }

    func testPendingBeatsBoth() {
        XCTAssertEqual(family(makePackage(status: nil, error: nil, endAt: nil)), .pending)
        XCTAssertEqual(family(makePackage(status: 200, error: nil, endAt: nil)), .pending)
        XCTAssertEqual(family(makePackage(status: 500, error: nil, endAt: nil)), .pending)
        XCTAssertEqual(family(makeRawPackage(endAt: nil, status: nil, errorCode: -1001)), .pending)
    }

    func testWebSocketBeatsEverything() {
        XCTAssertEqual(family(makePackage(status: 101, packageType: .websocket, endAt: nil)), .websocket)
        XCTAssertEqual(family(makePackage(status: 101, packageType: .websocket, endAt: 1_252)), .websocket)
        let err = NSError(domain: NSURLErrorDomain, code: -1005)
        XCTAssertEqual(family(makePackage(error: err, packageType: .websocket, endAt: 1_030)), .websocket)
        XCTAssertEqual(family(makePackage(status: 500, packageType: .websocket, endAt: 1_010)), .websocket)
    }

    func testPrecedenceIsTotal() {
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let all5 = makePackage(status: 404, error: err, packageType: .websocket, endAt: nil)
        XCTAssertEqual(family(all5), .websocket)

        let last4 = makeRawPackage(status: 404, errorCode: -1001, packageType: .http)
        XCTAssertEqual(family(last4), .pending)

        let last3 = makePackage(status: 404, error: err, packageType: .http, endAt: 1_010)
        XCTAssertEqual(family(last3), .transportError)
    }
}

// MARK: - §2 Display strings

final class AtlantisOverviewDisplayStringTests: XCTestCase {

    func testCaptions() {
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).caption, "SUCCESS")
        XCTAssertEqual(model(makePackage(status: 404), now: 2_000).caption, "CLIENT ERROR")
        XCTAssertEqual(model(makePackage(status: 503), now: 2_000).caption, "SERVER ERROR")
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        XCTAssertEqual(model(makePackage(error: err, endAt: 1_030), now: 2_000).caption, "TRANSPORT ERROR")
        XCTAssertEqual(model(makePackage(endAt: nil), now: 2_000).caption, "IN FLIGHT")
        XCTAssertEqual(model(wsPackage(), now: 60).caption, "101 SWITCHING PROTOCOLS")
    }

    func testCaptionCutListGuard() {
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let packages = [
            makePackage(status: 200), makePackage(status: 404), makePackage(status: 503),
            makePackage(error: err, endAt: 1_030), makePackage(endAt: nil), wsPackage()
        ]
        for p in packages {
            let caption = model(p, now: 2_000).caption
            XCTAssertFalse(caption.contains("HTTP/"))
            XCTAssertFalse(caption.contains("\u{00B7}"))
        }
    }

    func testMethodBadge() {
        XCTAssertEqual(model(makePackage(method: "get", packageType: .http), now: 2_000).methodBadge, "GET")
        XCTAssertEqual(model(makePackage(method: "POST", packageType: .http), now: 2_000).methodBadge, "POST")
        XCTAssertEqual(model(makePackage(method: "GET", url: "wss://socket.example.com/x", packageType: .websocket), now: 2_000).methodBadge, "WSS")
        XCTAssertEqual(model(makePackage(method: "GET", url: "ws://socket.example.com/x", packageType: .websocket), now: 2_000).methodBadge, "WS")
        XCTAssertEqual(model(makePackage(method: "GET", url: "https://socket.example.com/x", packageType: .websocket), now: 2_000).methodBadge, "WS")
    }

    func testStatusBlock() {
        func m(_ status: Int?, error: Error? = nil, endAt: TimeInterval? = 1_000.5) -> AtlantisOverviewModel {
            model(makePackage(status: status, error: error, endAt: endAt), now: 2_000)
        }
        XCTAssertEqual(m(200).statusNumeral, "200")
        XCTAssertEqual(m(200).reasonWord, "OK")
        XCTAssertNil(m(200).statusWord)

        XCTAssertEqual(m(201).reasonWord, "Created")
        XCTAssertEqual(m(204).reasonWord, "No Content")
        XCTAssertEqual(m(304).reasonWord, "Not Modified")
        XCTAssertEqual(m(404).reasonWord, "Not Found")
        XCTAssertEqual(m(418).reasonWord, "Client Error")
        XCTAssertEqual(m(500).reasonWord, "Server Error")
        XCTAssertEqual(m(504).reasonWord, "Timeout")
        XCTAssertEqual(m(250).reasonWord, "Success")
        XCTAssertEqual(m(350).reasonWord, "Redirect")
        XCTAssertEqual(m(150).reasonWord, "Informational")
        XCTAssertEqual(m(999).reasonWord, "Status")

        let noResp = m(nil, endAt: 1_000.5)
        XCTAssertEqual(noResp.statusNumeral, "\u{2014}")
        XCTAssertNil(noResp.reasonWord)

        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let transport = m(nil, error: err, endAt: 1_030)
        XCTAssertEqual(transport.statusNumeral, "-1001")
        XCTAssertNil(transport.reasonWord)
        XCTAssertEqual(transport.statusWord, "Failed")

        let pending = model(makePackage(endAt: nil), now: 2_000)
        XCTAssertNil(pending.statusNumeral)
        XCTAssertNil(pending.reasonWord)
        XCTAssertEqual(pending.statusWord, "In flight")

        let connected = model(wsPackage(endAt: nil), now: 60)
        XCTAssertEqual(connected.statusWord, "Connected")
        let closed = model(wsPackage(endAt: 1_200), now: 2_000)
        XCTAssertEqual(closed.statusWord, "Closed")
    }

    func testReasonWordRegressionGuard() {
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).reasonWord, "OK")
    }

    func testDurationValueAndSubLine() {
        let m1 = model(makePackage(status: 200, respBody: Data(count: 14_746), startAt: 1_000, endAt: 1_000.412), now: 2_000)
        XCTAssertEqual(m1.durationValue, "412 ms")
        XCTAssertEqual(m1.subLine, "14.4 KB")

        let m2 = model(makePackage(respBody: Data(), startAt: 1_000, endAt: 1_001.84), now: 2_000)
        XCTAssertEqual(m2.durationValue, "1.84 s")
        XCTAssertEqual(m2.subLine, "0 B")

        let m3 = model(makeRawPackage(startAt: 1_000, endAt: 1_030, status: nil, errorCode: -1001), now: 2_000)
        XCTAssertEqual(m3.durationValue, "30.00 s")
        XCTAssertEqual(m3.subLine, "no response")

        let m4 = model(makePackage(startAt: 1_000, endAt: nil), now: 1_001.84)
        XCTAssertEqual(m4.durationValue, "1.84 s")
        XCTAssertEqual(m4.subLine, "elapsed")

        let m5 = model(wsPackage(startAt: 1_000, endAt: nil, messages: (0..<103).map { _ in wsMessage(.receive) }), now: 1_252)
        XCTAssertEqual(m5.durationValue, "4:12")
        XCTAssertEqual(m5.subLine, "103 frames")

        let m6 = model(wsPackage(messages: [wsMessage(.receive)]), now: 60)
        XCTAssertEqual(m6.subLine, "1 frame")

        let m7 = model(wsPackage(), now: 60)
        XCTAssertEqual(m7.subLine, "no frames")

        for m in [m1, m2, m3, m4, m5, m6, m7] {
            XCTAssertFalse(m.subLine.contains("cache"))
            XCTAssertFalse(m.subLine.contains("\u{00B7}"))
        }
    }

    func testPathHostErrorCard() {
        let m1 = model(makePackage(url: "https://api.acme-cloud.com/v1/users/8842/preferences"), now: 2_000)
        XCTAssertEqual(m1.pathText, "/v1/users/8842/preferences")
        XCTAssertEqual(m1.hostText, "api.acme-cloud.com")

        let m2 = model(makePackage(url: "https://api.acme-cloud.com/v1/users?page=2"), now: 2_000)
        XCTAssertEqual(m2.pathText, "/v1/users?page=2")

        let m3 = model(makePackage(url: "https://api.acme-cloud.com"), now: 2_000)
        XCTAssertEqual(m3.pathText, "https://api.acme-cloud.com")
        XCTAssertEqual(m3.hostText, "api.acme-cloud.com")

        let err = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let m4 = model(makePackage(error: err, endAt: 1_030), now: 2_000)
        XCTAssertEqual(m4.errorHeadline, "The request timed out.")
        XCTAssertEqual(m4.errorCodeLine, "Error -1001")

        let m5 = model(makePackage(status: 200), now: 2_000)
        XCTAssertNil(m5.errorHeadline)
        XCTAssertNil(m5.errorCodeLine)

        XCTAssertFalse(m4.errorCodeLine!.contains("NSURLErrorDomain"))
        XCTAssertFalse(m4.errorCodeLine!.contains("NSURLErrorTimedOut"))
        XCTAssertFalse(m4.errorCodeLine!.contains("("))
        XCTAssertFalse(m4.errorCodeLine!.contains("\u{00B7}"))

        let m6 = model(wsPackage(url: "wss://socket.acme-cloud.com/realtime/v1/presence"), now: 60)
        XCTAssertEqual(m6.hostText, "socket.acme-cloud.com")
        XCTAssertFalse(m6.hostText.contains("\u{00B7}"))
        XCTAssertFalse(m6.hostText.contains("json"))
    }

    func testTimingCardStrings() {
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).timingTitle, "Timing")
        XCTAssertNil(model(makePackage(status: 200), now: 2_000).timingAccessory)
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).timingSecondRowLabel, "Duration")

        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let transport = model(makePackage(error: err, endAt: 1_030), now: 2_000)
        XCTAssertEqual(transport.timingTitle, "Timing")
        XCTAssertNil(transport.timingAccessory)
        XCTAssertEqual(transport.timingSecondRowLabel, "Duration")

        let pending = model(makePackage(endAt: nil), now: 2_000)
        XCTAssertEqual(pending.timingTitle, "Timing \u{00B7} live")
        XCTAssertEqual(pending.timingAccessory, "running")
        XCTAssertEqual(pending.timingSecondRowLabel, "Elapsed")

        let connected = model(wsPackage(endAt: nil), now: 60)
        XCTAssertEqual(connected.timingTitle, "Timing \u{00B7} live")
        XCTAssertEqual(connected.timingAccessory, "running")
        XCTAssertEqual(connected.timingSecondRowLabel, "Elapsed")

        let closed = model(wsPackage(endAt: 1_200), now: 2_000)
        XCTAssertEqual(closed.timingTitle, "Timing")
        XCTAssertNil(closed.timingAccessory)
        XCTAssertEqual(closed.timingSecondRowLabel, "Duration")
    }

    func testStartedFormatter() {
        let gmt = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(AtlantisFormat.started(1_700_000_458.204, now: 1_700_000_500, timeZone: gmt), "Today 22:20:58.204")
        XCTAssertEqual(AtlantisFormat.started(1_700_000_458.204, now: 1_700_086_900, timeZone: gmt), "Yesterday 22:20:58.204")
        XCTAssertEqual(AtlantisFormat.started(1_700_000_458.204, now: 1_700_260_000, timeZone: gmt), "2023-11-14 22:20:58.204")
        XCTAssertEqual(AtlantisFormat.started(1_699_939_838.000, now: 1_699_950_000, timeZone: gmt), "Today 5:30:38.000")
    }

    func testUptimeFormatter() {
        XCTAssertEqual(AtlantisFormat.uptime(0), "0:00")
        XCTAssertEqual(AtlantisFormat.uptime(-5), "0:00")
        XCTAssertEqual(AtlantisFormat.uptime(9), "0:09")
        XCTAssertEqual(AtlantisFormat.uptime(59.9), "0:59")
        XCTAssertEqual(AtlantisFormat.uptime(60), "1:00")
        XCTAssertEqual(AtlantisFormat.uptime(252), "4:12")
        XCTAssertEqual(AtlantisFormat.uptime(3_599), "59:59")
        XCTAssertEqual(AtlantisFormat.uptime(3_600), "1:00:00")
        XCTAssertEqual(AtlantisFormat.uptime(3_725), "1:02:05")
        XCTAssertEqual(AtlantisFormat.uptime(86_399), "23:59:59")
    }

    func testElapsedFormatter() {
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_000), "0 ms")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 999), "0 ms")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_000.412), "412 ms")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_000.9994), "999 ms")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_001), "1.00 s")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_001.84), "1.84 s")
        XCTAssertEqual(AtlantisFormat.elapsed(startAt: 1_000, now: 1_030), "30.00 s")
    }

    func testDetailRowsAndAccessories() {
        let reqHeaders = (0..<12).map { Header(key: "h\($0)", value: "v\($0)") }
        let respHeaders = [Header(key: "Content-Type", value: "application/json")] + (0..<17).map { Header(key: "h\($0)", value: "v\($0)") }
        let p1 = makePackage(reqHeaders: reqHeaders, reqBody: nil, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 14_540))
        let rows1 = model(p1, now: 2_000).detailRows
        XCTAssertEqual(rows1[0], AtlantisOverviewDetailRow(title: "Request Headers", accessory: .count(12), isTappable: true, iconKind: .accent))
        XCTAssertEqual(rows1[1], AtlantisOverviewDetailRow(title: "Response Headers", accessory: .count(18), isTappable: true, iconKind: .accent))
        XCTAssertEqual(rows1[2], AtlantisOverviewDetailRow(title: "Request Body", accessory: .word("No body"), isTappable: false, iconKind: .neutral))
        XCTAssertEqual(rows1[3], AtlantisOverviewDetailRow(title: "Response Body", accessory: .badge("JSON", "14.2 KB"), isTappable: true, iconKind: .success))

        let p2 = makePackage(reqHeaders: [], respHeaders: [])
        let rows2 = model(p2, now: 2_000).detailRows
        XCTAssertEqual(rows2[0].accessory, .count(0))
        XCTAssertFalse(rows2[0].isTappable)
        XCTAssertEqual(rows2[1].accessory, .count(0))
        XCTAssertFalse(rows2[1].isTappable)

        let p3 = makePackage(respBody: Data())
        let rows3 = model(p3, now: 2_000).detailRows
        XCTAssertEqual(rows3[3], AtlantisOverviewDetailRow(title: "Response Body", accessory: .word("No body"), isTappable: false, iconKind: .neutral))
    }

    func testTransportErrorStatTiles() {
        let reqHeaders = [Header(key: "content-encoding", value: "gzip")] + (0..<8).map { Header(key: "h\($0)", value: "v\($0)") }
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let p = makePackage(reqHeaders: reqHeaders,
                             reqBody: binaryBody(count: Int(1.1 * 1024 * 1024)),
                             status: nil,
                             respBody: Data(),
                             error: err,
                             endAt: 1_030)
        let tiles = model(p, now: 2_000).statTiles(for: .transportError)
        XCTAssertEqual(tiles.count, 4)
        XCTAssertEqual(tiles[0].title, "Req Headers")
        XCTAssertEqual(tiles[0].content, .value("9", detail: "content-encoding: gzip", iconKind: .accent))
        XCTAssertTrue(tiles[0].isLive)
        XCTAssertEqual(tiles[1], AtlantisOverviewStatTile(title: "Res Headers", content: .dimmed("Never received"), isLive: false))
        XCTAssertEqual(tiles[3], AtlantisOverviewStatTile(title: "Response Body", content: .dimmed("Nothing received"), isLive: false))
        if case .badge(let badge, let size, let detail, _) = tiles[2].content {
            XCTAssertEqual(badge, "GZIP")
            XCTAssertEqual(size, "1.1 MB")
            XCTAssertNil(detail)
        } else {
            XCTFail("expected badge content")
        }
        XCTAssertTrue(tiles[2].isLive)

        let pEmptyReqBody = makePackage(reqBody: nil, status: nil, error: err, endAt: 1_030)
        let tilesEmpty = model(pEmptyReqBody, now: 2_000).statTiles(for: .transportError)
        XCTAssertEqual(tilesEmpty[2], AtlantisOverviewStatTile(title: "Request Body", content: .dimmed("Nothing sent"), isLive: false))
    }

    func testPendingStatTiles() {
        let reqHeaders = [Header(key: "content-type", value: "application/pdf")] + (0..<10).map { Header(key: "h\($0)", value: "v\($0)") }
        let p = makePackage(reqHeaders: reqHeaders, reqBody: binaryBody(count: Int(2.4 * 1024 * 1024)), endAt: nil)
        let tiles = model(p, now: 2_000).statTiles(for: .pending)
        XCTAssertEqual(tiles.count, 3)
        XCTAssertEqual(tiles[0].content, .value("11", detail: "content-type: application/pdf", iconKind: .accent))
        XCTAssertTrue(tiles[0].isLive)
        if case .badge(let badge, let size, let detail, _) = tiles[1].content {
            XCTAssertEqual(badge, "PDF")
            XCTAssertEqual(size, "2.4 MB")
            XCTAssertEqual(detail, "sending\u{2026}")
        } else {
            XCTFail("expected badge content")
        }
        XCTAssertTrue(tiles[1].isLive)
        XCTAssertEqual(tiles[2], AtlantisOverviewStatTile(title: "Response", content: .skeleton(label: "Waiting for headers\u{2026}"), isLive: false))

        let pNoHeaders = makePackage(reqHeaders: [], endAt: nil)
        let tilesNoHeaders = model(pNoHeaders, now: 2_000).statTiles(for: .pending)
        XCTAssertEqual(tilesNoHeaders[0].content, .value("0", detail: nil, iconKind: .accent))
        XCTAssertTrue(tilesNoHeaders[0].isLive)
    }

    func testStatTileCutListGuard() {
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        let transportTiles = model(makePackage(status: nil, error: err, endAt: 1_030), now: 2_000).statTiles(for: .transportError)
        let pendingTiles = model(makePackage(endAt: nil), now: 2_000).statTiles(for: .pending)
        for tile in transportTiles + pendingTiles {
            let text = "\(tile)"
            XCTAssertFalse(text.contains("fully sent"))
            XCTAssertFalse(text.contains("of 2.4 MB sent"))
            XCTAssertFalse(text.contains("%"))
            XCTAssertFalse(text.contains("Replay"))
            XCTAssertFalse(text.contains("Cancel"))
        }
    }

    func testFooterAndNavTitle() {
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).navigationTitle, "Request")
        XCTAssertEqual(model(makePackage(status: 200), now: 2_000).footerAction, .copyCurl)
        XCTAssertEqual(model(makePackage(status: 404), now: 2_000).footerAction, .copyCurl)
        XCTAssertEqual(model(makePackage(status: 503), now: 2_000).footerAction, .copyCurl)
        let err = NSError(domain: NSURLErrorDomain, code: -1001)
        XCTAssertEqual(model(makePackage(error: err, endAt: 1_030), now: 2_000).footerAction, .copyCurl)
        XCTAssertNil(model(makePackage(endAt: nil), now: 2_000).footerAction)
        let ws = model(wsPackage(), now: 60)
        XCTAssertEqual(ws.navigationTitle, "Socket")
        XCTAssertNil(ws.footerAction)
    }
}

// MARK: - §3 WebSocket folds, sparkline, liveness

final class AtlantisOverviewWebSocketTests: XCTestCase {

    func testCountsAndByteTotals() {
        let messages = [
            wsMessage(.receive, string: "abc"),
            wsMessage(.receive, data: Data(count: 10)),
            wsMessage(.send, string: "hi"),
            wsMessage(.pingPong, data: Data(count: 4)),
            wsMessage(.sendCloseMessage)
        ]
        let m = model(wsPackage(startAt: 0, endAt: nil, messages: messages), now: 60)
        XCTAssertEqual(m.receivedCount, 2)
        XCTAssertEqual(m.sentCount, 1)
        XCTAssertEqual(m.receivedBytes, 13)
        XCTAssertEqual(m.sentBytes, 2)
        XCTAssertEqual(m.frameCount, 5)
        XCTAssertEqual(m.receivedBytesText, "13 B")
        XCTAssertEqual(m.sentBytesText, "2 B")
    }

    /// Reduced from spec §3.2's exact per-case table: `createdAt` cannot be
    /// injected (see file header). Asserts the format contract and the true
    /// zero-message case instead of specific windowed counts.
    func testRateFormat() {
        XCTAssertEqual(model(wsPackage(), now: 300).rateText, "0.0/s")
        let m = model(wsPackage(messages: (0..<10).map { _ in wsMessage(.receive) }), now: Date().timeIntervalSince1970 + 1)
        XCTAssertTrue(m.rateText.range(of: #"^\d+\.\d/s$"#, options: .regularExpression) != nil)
    }

    func testUptime() {
        XCTAssertEqual(model(wsPackage(startAt: 1_000, endAt: nil), now: 1_252).durationValue, "4:12")
        XCTAssertEqual(model(wsPackage(startAt: 1_000, endAt: 1_252), now: 9_999).durationValue, "4:12")
        XCTAssertEqual(model(wsPackage(startAt: 1_000, endAt: nil), now: 1_000).durationValue, "0:00")
    }

    func testConnectedClosedPredicate() {
        XCTAssertTrue(model(wsPackage(endAt: nil, messages: [wsMessage(.receive)]), now: 60).isConnected)
        XCTAssertTrue(model(wsPackage(endAt: nil, messages: [wsMessage(.send)]), now: 60).isConnected)
        XCTAssertTrue(model(wsPackage(endAt: nil, messages: [wsMessage(.pingPong)]), now: 60).isConnected)
        XCTAssertTrue(model(wsPackage(endAt: nil, messages: []), now: 60).isConnected)
        XCTAssertFalse(model(wsPackage(endAt: nil, messages: [wsMessage(.sendCloseMessage)]), now: 60).isConnected)
        XCTAssertFalse(model(wsPackage(endAt: 1_252, messages: [wsMessage(.receive)]), now: 9_999).isConnected)
        XCTAssertFalse(model(wsPackage(endAt: 1_252, messages: []), now: 9_999).isConnected)

        let trailingReceive = [
            wsMessage(.receive), wsMessage(.send), wsMessage(.sendCloseMessage),
            wsMessage(.pingPong), wsMessage(.receive)
        ]
        XCTAssertTrue(model(wsPackage(endAt: nil, messages: trailingReceive), now: 60).isConnected)
    }

    func testSparklineNoMessages() {
        let buckets = model(wsPackage(startAt: 0, endAt: 140, messages: []), now: 140).sparkline
        XCTAssertEqual(buckets.count, 14)
        for b in buckets {
            XCTAssertEqual(b, AtlantisSparklineBucket(count: 0, direction: .none, heightFraction: 0.08))
        }
    }

    func testSparklineZeroLengthWindow() {
        let buckets = model(wsPackage(startAt: 1_000, endAt: nil, messages: []), now: 1_000).sparkline
        XCTAssertEqual(buckets.count, 14)
        for b in buckets {
            XCTAssertEqual(b, AtlantisSparklineBucket(count: 0, direction: .none, heightFraction: 0.08))
        }
    }

    /// Structural check standing in for spec §3.5.1-3.5.10's per-bucket assertions,
    /// which require offsetting real messages by exact seconds — not possible
    /// without an injectable `createdAt` (see file header).
    func testSparklineStructure() {
        let messages = (0..<20).map { _ in wsMessage(.receive) }
        let now = Date().timeIntervalSince1970
        let buckets = model(wsPackage(startAt: now - 200, endAt: now, messages: messages), now: now).sparkline
        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.count }, messages.count)
        for b in buckets {
            XCTAssertGreaterThanOrEqual(b.heightFraction, 0.08)
            XCTAssertLessThanOrEqual(b.heightFraction, 1.0)
        }
    }

    func testSparklineWindowLabel() {
        XCTAssertEqual(model(wsPackage(startAt: 0, endAt: 600, messages: []), now: 600).sparklineWindowLabel, "4 min")
        XCTAssertEqual(model(wsPackage(startAt: 0, endAt: 140, messages: []), now: 140).sparklineWindowLabel, "2:20")
    }

    func testMessagePreviewsCountAndOrdering() {
        let messages = [10, 20, 30, 40, 50].map { _ in wsMessage(.receive) }
        let previews = model(wsPackage(messages: messages), now: 60).messagePreviews
        XCTAssertEqual(previews.count, 3)

        let m2 = model(wsPackage(messages: [wsMessage(.receive), wsMessage(.receive)]), now: 60)
        XCTAssertEqual(m2.messagePreviews.count, 2)

        let m3 = model(wsPackage(messages: []), now: 60)
        XCTAssertTrue(m3.messagePreviews.isEmpty)
        XCTAssertNil(m3.seeAllLabel)

        let messages103 = (0..<103).map { _ in wsMessage(.receive) }
        XCTAssertEqual(model(wsPackage(messages: messages103), now: 200).seeAllLabel, "See all 103")
    }

    func testMessagePreviewsNewestFirst() {
        let m1 = wsMessage(.receive, string: "first")
        let m2 = wsMessage(.receive, string: "second")
        let m3 = wsMessage(.receive, string: "third")
        let previews = model(wsPackage(messages: [m1, m2, m3]), now: 60).messagePreviews
        XCTAssertEqual(previews.map { $0.bodyPreview }, ["third", "second", "first"])
    }

    func testChipLabels() {
        XCTAssertEqual(model(wsPackage(messages: [wsMessage(.receive)]), now: 60).messagePreviews[0].chipLabel, "RECV")
        XCTAssertEqual(model(wsPackage(messages: [wsMessage(.send)]), now: 60).messagePreviews[0].chipLabel, "SENT")
        XCTAssertEqual(model(wsPackage(messages: [wsMessage(.pingPong)]), now: 60).messagePreviews[0].chipLabel, "PING")
        XCTAssertEqual(model(wsPackage(messages: [wsMessage(.sendCloseMessage)]), now: 60).messagePreviews[0].chipLabel, "CLOSE")
    }

    func testMessageSizeText() {
        let m312 = model(wsPackage(messages: [wsMessage(.receive, data: Data(count: 312))]), now: 60)
        XCTAssertEqual(m312.messagePreviews[0].sizeText, "312 B")
        let m1434 = model(wsPackage(messages: [wsMessage(.receive, string: String(repeating: "a", count: 1_434))]), now: 60)
        XCTAssertEqual(m1434.messagePreviews[0].sizeText, "1.4 KB")
    }

    func testBinaryBodyPreview() {
        let invalidUTF8 = Data([0xC3, 0x28, 0xA0, 0xA1, 0xE2, 0x28, 0xA1, 0xFF])
        XCTAssertEqual(invalidUTF8.count, 8)
        let m = model(wsPackage(messages: [wsMessage(.receive, data: invalidUTF8)]), now: 60)
        XCTAssertEqual(m.messagePreviews[0].bodyPreview, "\u{27E8}binary, 8 bytes\u{27E9}")
    }
}

// MARK: - §4.10/4.11 timer gating (headless portion)

final class AtlantisOverviewTimerGatingTests: XCTestCase {

    func testIsLiveGatesOnPendingAndTearsDownOnComplete() {
        let p = makePackage(endAt: nil)
        XCTAssertTrue(model(p, now: 2_000).isLive)
        p.updateDidComplete(nil)
        let after = model(p, now: 2_000)
        XCTAssertFalse(after.isLive)
        XCTAssertEqual(after.family, .success)
        XCTAssertNil(after.timingAccessory)
        XCTAssertEqual(after.timingSecondRowLabel, "Duration")
    }

    func testElapsedTextSingleSource() {
        let m = model(makePackage(endAt: nil), now: 2_000)
        XCTAssertTrue(m.isLive)
        XCTAssertEqual(m.elapsedText(now: 1_001.84), "1.84 s")
    }
}

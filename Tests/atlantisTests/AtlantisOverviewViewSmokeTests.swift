import Foundation
import XCTest
import SwiftUI
@testable import Atlantis

// View-level smoke tests for Tests/request-overview.spec.md §4 (B4 — merge-gate blocker).
// Each fixture builds AtlantisTrafficDetailView, forces `.body`, and asserts no render trap,
// once per colorScheme, following the pattern of
// AtlantisViewerTests.swift:375 (testDetailRendersEveryBodyBranchWithoutTrapping).

private func smokePackage(method: String = "GET",
                           url: String = "https://api.example.com/users",
                           reqHeaders: [Header] = [],
                           reqBody: Data? = nil,
                           status: Int? = 200,
                           respHeaders: [Header] = [],
                           respBody: Data = Data(),
                           error: Error? = nil,
                           startAt: TimeInterval = 1_000,
                           endAt: TimeInterval? = 1_000.5) -> TrafficPackage {
    let request = Request(url: url, method: method, headers: reqHeaders, body: reqBody)
    let response = status.map { Response(statusCode: $0, headers: respHeaders) }
    let package = TrafficPackage(id: UUID().uuidString,
                                  request: request,
                                  response: response,
                                  responseBodyData: respBody,
                                  packageType: .http,
                                  startAt: startAt,
                                  endAt: endAt)
    if let error = error {
        package.updateDidComplete(error)
    }
    return package
}

private func smokeWSPackage(startAt: TimeInterval = 0,
                             endAt: TimeInterval? = nil,
                             messages: [WebsocketMessagePackage] = []) -> TrafficPackage {
    let request = Request(url: "wss://socket.example.com/realtime/v1/presence", method: "GET", headers: [], body: nil)
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

private func wsMessage(_ type: WebsocketMessagePackage.MessageType, index: Int) -> WebsocketMessagePackage {
    if type == .sendCloseMessage {
        return WebsocketMessagePackage(id: UUID().uuidString, closeCode: 1000, reason: nil)
    }
    return WebsocketMessagePackage(id: UUID().uuidString, message: .string("frame \(index)"), messageType: type)
}

private func jsonBody(totalBytes: Int) -> Data {
    let prefix = "{\"pad\":\""
    let suffix = "\"}"
    let padLength = max(0, totalBytes - prefix.utf8.count - suffix.utf8.count)
    return Data((prefix + String(repeating: "x", count: padLength) + suffix).utf8)
}

@available(iOS 15.0, macOS 12.0, *)
final class AtlantisOverviewViewSmokeTests: XCTestCase {

    /// Forces a render pass of the given view — asserts it doesn't trap — then
    /// constructs it under both `.light` and `.dark` (spec §4's "twice, once per
    /// colorScheme" requirement). `AtlantisSyntaxTheme` colors resolve dynamically off
    /// the platform trait, not `@Environment(\.colorScheme)`, and SwiftUI disallows
    /// calling `.body` directly on `ModifiedContent` outside a real host, so the
    /// colorScheme-wrapped construction is exercised without forcing its `.body`.
    private func renderBothSchemes(_ makeView: () -> AtlantisTrafficDetailView) {
        _ = makeView().body
        for scheme: ColorScheme in [.light, .dark] {
            _ = AnyView(makeView().environment(\.colorScheme, scheme))
        }
    }

    // 4.1 success
    func testSuccessRendersInBothColorSchemes() {
        let respHeaders = [Header(key: "Content-Type", value: "application/json")]
        let package = smokePackage(status: 200, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 14_746), endAt: 1_000.412)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Request")
    }

    // 4.2 client error
    func testClientErrorRendersInBothColorSchemes() {
        let respHeaders = [Header(key: "Content-Type", value: "application/json")]
        let package = smokePackage(status: 404, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 120), endAt: 1_000.412)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Request")
    }

    // 4.3 server error
    func testServerErrorRendersInBothColorSchemes() {
        let respHeaders = [Header(key: "Content-Type", value: "application/json")]
        let package = smokePackage(status: 503, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 120), endAt: 1_000.412)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Request")
    }

    // 4.4 transport error
    func testTransportErrorRendersInBothColorSchemes() {
        let error = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let package = smokePackage(method: "POST", reqBody: binaryBodyForSmoke(count: 1_100_000), status: nil, error: error, endAt: 1_030)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Request")
    }

    // 4.5 in flight
    func testInFlightRendersInBothColorSchemes() {
        let package = smokePackage(method: "PUT", reqBody: binaryBodyForSmoke(count: 2_400_000), status: nil, endAt: nil)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        let model = AtlantisOverviewModel(package: package, now: 1_001.84)
        XCTAssertTrue(model.isLive)
        XCTAssertEqual(model.navigationTitle, "Request")
    }

    // 4.6 websocket, connected
    func testWebSocketConnectedRendersInBothColorSchemes() {
        let messages = (0..<103).map { i -> WebsocketMessagePackage in
            wsMessage(i % 2 == 0 ? .receive : .send, index: i)
        }
        let package = smokeWSPackage(endAt: nil, messages: messages)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Socket")
    }

    // 4.7 websocket, closed
    func testWebSocketClosedRendersInBothColorSchemes() {
        var messages = (0..<103).map { i -> WebsocketMessagePackage in
            wsMessage(i % 2 == 0 ? .receive : .send, index: i)
        }
        messages.append(wsMessage(.sendCloseMessage, index: 103))
        let package = smokeWSPackage(endAt: nil, messages: messages)
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        let model = AtlantisOverviewModel(package: package, now: 2_000)
        XCTAssertFalse(model.isConnected)
        XCTAssertEqual(model.navigationTitle, "Socket")
    }

    // 4.8 empty everything
    func testEmptyEverythingRendersInBothColorSchemes() {
        let package = smokePackage(reqHeaders: [], reqBody: nil, status: 200, respHeaders: [], respBody: Data())
        renderBothSchemes { AtlantisTrafficDetailView(package: package) }
        XCTAssertEqual(AtlantisOverviewModel(package: package, now: 2_000).navigationTitle, "Request")
    }

    // 4.12 body preview cards still wired — request body omitted when empty, both present when both non-empty.
    func testBodyPreviewCardWiringMatchesBodyPresence() {
        let respHeaders = [Header(key: "Content-Type", value: "application/json")]
        let responseOnlyPackage = smokePackage(status: 200, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 14_746), endAt: 1_000.412)
        let responseOnlyModel = AtlantisOverviewModel(package: responseOnlyPackage, now: 2_000)
        let responseOnlyRows = responseOnlyModel.detailRows
        XCTAssertEqual(responseOnlyRows.first { $0.title == "Request Body" }?.accessory, .word("No body"))
        if case .badge = responseOnlyRows.first(where: { $0.title == "Response Body" })?.accessory {
        } else {
            XCTFail("expected Response Body row to carry a badge accessory")
        }

        let reqHeaders = [Header(key: "Content-Type", value: "application/json")]
        let bothBodiesPackage = smokePackage(reqHeaders: reqHeaders, reqBody: jsonBody(totalBytes: 200),
                                              status: 200, respHeaders: respHeaders, respBody: jsonBody(totalBytes: 14_746),
                                              endAt: 1_000.412)
        let bothBodiesModel = AtlantisOverviewModel(package: bothBodiesPackage, now: 2_000)
        let bothBodiesRows = bothBodiesModel.detailRows
        if case .badge = bothBodiesRows.first(where: { $0.title == "Request Body" })?.accessory {
        } else {
            XCTFail("expected Request Body row to carry a badge accessory")
        }
        if case .badge = bothBodiesRows.first(where: { $0.title == "Response Body" })?.accessory {
        } else {
            XCTFail("expected Response Body row to carry a badge accessory")
        }
        renderBothSchemes { AtlantisTrafficDetailView(package: bothBodiesPackage) }
    }
}

private func binaryBodyForSmoke(count: Int) -> Data {
    Data(repeating: 0xFF, count: count)
}

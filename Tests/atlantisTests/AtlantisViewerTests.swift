import Foundation
import XCTest
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import Atlantis

// Fixture helper per Tests/viewer.spec.md §0.
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

// MARK: - 1. AtlantisTrafficStore

final class AtlantisTrafficStoreTests: XCTestCase {

    func testUpsertInsertsNewId() {
        let store = AtlantisTrafficStore()
        store.upsert(makePackage(id: "a"))
        XCTAssertEqual(store.packages.count, 1)
        XCTAssertEqual(store.packages[0].id, "a")
    }

    func testUpsertByIdReplacesInPlace() {
        let store = AtlantisTrafficStore()
        let p = makePackage(id: "a")
        store.upsert(p)
        p.appendResponseData(Data("more".utf8))
        store.upsert(p)
        XCTAssertEqual(store.packages.count, 1)
        XCTAssertTrue(store.packages[0] === p)
    }

    func testRingBufferEvictionAtCapacity() {
        let store = AtlantisTrafficStore(capacity: 3)
        ["a", "b", "c", "d"].forEach { store.upsert(makePackage(id: $0)) }
        XCTAssertEqual(store.packages.count, 3)
        XCTAssertEqual(store.packages.map { $0.id }, ["b", "c", "d"])
    }

    func testEvictionKeepsIndexMapConsistent() {
        let store = AtlantisTrafficStore(capacity: 3)
        ["a", "b", "c"].forEach { store.upsert(makePackage(id: $0)) }
        store.upsert(makePackage(id: "b"))
        XCTAssertEqual(store.packages.count, 3)
        store.upsert(makePackage(id: "d"))
        XCTAssertEqual(store.packages.count, 3)
        XCTAssertEqual(store.packages.map { $0.id }, ["b", "c", "d"])
    }

    func testClearEmptiesEverything() {
        let store = AtlantisTrafficStore()
        ["a", "b", "c"].forEach { store.upsert(makePackage(id: $0)) }
        store.clear()
        XCTAssertTrue(store.packages.isEmpty)
        store.upsert(makePackage(id: "a"))
        XCTAssertEqual(store.packages.count, 1)
    }

    func testPauseBlocksInsertsAllowsInPlaceUpdate() {
        let store = AtlantisTrafficStore()
        store.isPaused = true
        store.upsert(makePackage(id: "x"))
        XCTAssertTrue(store.packages.isEmpty)

        store.isPaused = false
        let x = makePackage(id: "x")
        store.upsert(x)
        XCTAssertEqual(store.packages.count, 1)

        store.isPaused = true
        x.appendResponseData(Data("more".utf8))
        XCTAssertEqual(store.packages[0].responseBodyData, x.responseBodyData)
    }

    func testRemoveByIdentity() {
        let store = AtlantisTrafficStore()
        ["a", "b", "c"].forEach { store.upsert(makePackage(id: $0)) }
        store.remove(store.packages[1])
        XCTAssertEqual(store.packages.map { $0.id }, ["a", "c"])
        store.upsert(makePackage(id: "b"))
        XCTAssertEqual(store.packages.map { $0.id }, ["a", "c", "b"])
    }
}

// MARK: - 4. AtlantisTrafficFilter

final class AtlantisTrafficFilterTests: XCTestCase {
    private let g = makePackage(id: "g", method: "GET", url: "https://api.example.com/users", status: 200)
    private let p = makePackage(id: "p", method: "POST", url: "https://api.example.com/orders", status: 201)
    private let e = makePackage(id: "e", method: "GET", url: "https://api.example.com/fail", status: 500)
    private let x = makePackage(id: "x", method: "GET", url: "https://api.example.com/pending", status: nil)
    private let err = makePackage(id: "err", method: "GET", url: "https://api.example.com/boom", status: nil,
                                  error: NSError(domain: "test", code: 1))

    private var all: [TrafficPackage] { [g, p, e, x, err] }

    func testEmptyQueryAllPass() {
        let result = AtlantisTrafficFilter.apply(all, query: "", errorsOnly: false)
        XCTAssertEqual(result.count, all.count)
        XCTAssertEqual(result.map { $0.id }, all.map { $0.id })
    }

    func testCaseInsensitiveURLPathMatch() {
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "ORDERS", errorsOnly: false).map { $0.id }, ["p"])
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "/fail", errorsOnly: false).map { $0.id }, ["e"])
    }

    func testMethodMatch() {
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "post", errorsOnly: false).map { $0.id }, ["p"])
    }

    func testStatusMatch() {
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "500", errorsOnly: false).map { $0.id }, ["e"])
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "20", errorsOnly: false).map { $0.id }, ["g", "p"])
    }

    func testErrorsOnlyPredicate() {
        let result = AtlantisTrafficFilter.apply(all, query: "", errorsOnly: true)
        XCTAssertEqual(Set(result.map { $0.id }), Set(["e", "err"]))
    }

    func testErrorsOnlyAndQueryCombine() {
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "boom", errorsOnly: true).map { $0.id }, ["err"])
        XCTAssertEqual(AtlantisTrafficFilter.apply(all, query: "users", errorsOnly: true).map { $0.id }, [])
    }

    func testWhitespaceOnlyQueryIsEmpty() {
        let result = AtlantisTrafficFilter.apply(all, query: "   ", errorsOnly: false)
        XCTAssertEqual(result.count, all.count)
    }
}

// MARK: - 5. HAR

final class AtlantisTrafficHARTests: XCTestCase {

    func testEntryRequestFields() {
        let headers = [Header(key: "Content-Type", value: "application/json")]
        let body = Data(#"{"name":"Ada"}"#.utf8)
        let package = makePackage(method: "POST", url: "https://api.example.com/users",
                                  reqHeaders: headers, reqBody: body)
        let entry = package.harEntry()
        let request = entry["request"] as! [String: Any]
        XCTAssertEqual(request["method"] as? String, "POST")
        XCTAssertEqual(request["url"] as? String, "https://api.example.com/users")
        let reqHeadersOut = request["headers"] as! [[String: Any]]
        XCTAssertEqual(reqHeadersOut.count, 1)
        XCTAssertEqual(reqHeadersOut[0]["name"] as? String, "Content-Type")
        XCTAssertEqual(request["bodySize"] as? Int, body.count)
        let postData = request["postData"] as! [String: Any]
        XCTAssertEqual(postData["text"] as? String, String(data: body, encoding: .utf8))
        XCTAssertNil(postData["encoding"])
    }

    func testEntryResponseFields() {
        let respBody = Data("hello".utf8)
        let package = makePackage(status: 200, respBody: respBody)
        let entry = package.harEntry()
        let response = entry["response"] as! [String: Any]
        XCTAssertEqual(response["status"] as? Int, 200)
        let content = response["content"] as! [String: Any]
        XCTAssertEqual(content["size"] as? Int, respBody.count)
        XCTAssertEqual(content["text"] as? String, "hello")
    }

    func testBinaryBodyBase64Encoding() {
        let binary = Data([0x00, 0x01, 0x02, 0xFF])
        let package = makePackage(status: 200, respBody: binary)
        let entry = package.harEntry()
        let response = entry["response"] as! [String: Any]
        let content = response["content"] as! [String: Any]
        XCTAssertEqual(content["encoding"] as? String, "base64")
        XCTAssertEqual(content["text"] as? String, binary.base64EncodedString())
    }

    func testTimingsSumEqualsTime() {
        let package = makePackage(startAt: 1_000, endAt: 1_001.5)
        let entry = package.harEntry()
        let time = entry["time"] as! Double
        let timings = entry["timings"] as! [String: Any]
        let send = timings["send"] as! Int
        let wait = timings["wait"] as! Double
        let receive = timings["receive"] as! Int
        XCTAssertEqual(Double(send) + wait + Double(receive), time, accuracy: 0.001)
        XCTAssertEqual(time, 1500, accuracy: 0.001)
    }

    func testNoResponseRow() {
        let package = makePackage(status: nil, endAt: nil)
        let entry = package.harEntry()
        let response = entry["response"] as! [String: Any]
        XCTAssertEqual(response["status"] as? Int, 0)
        XCTAssertEqual(response["statusText"] as? String, "")
        let content = response["content"] as! [String: Any]
        XCTAssertEqual(content["text"] as? String, "")
        XCTAssertEqual(entry["time"] as? Double, 0)
    }

    func testStartedDateTimeISO8601() {
        let package = makePackage(startAt: 1_000)
        let entry = package.harEntry()
        let started = entry["startedDateTime"] as! String
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#)
        XCTAssertEqual(regex.numberOfMatches(in: started, range: NSRange(started.startIndex..., in: started)), 1)
    }

    func testExportHAREnvelope() throws {
        let store = AtlantisTrafficStore()
        store.upsert(makePackage(id: "a"))
        store.upsert(makePackage(id: "b"))
        let data = store.exportHAR()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let log = json["log"] as! [String: Any]
        XCTAssertEqual(log["version"] as? String, "1.2")
        let creator = log["creator"] as! [String: Any]
        XCTAssertEqual(creator["name"] as? String, "Atlantis")
        let entries = log["entries"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0]["request"] as? [String: Any] != nil, true)
    }

    func testWebsocketMessagesUnderExtensionKey() {
        let package = makePackage(packageType: .websocket)
        package.setWebsocketMessagePackage(package: WebsocketMessagePackage(id: package.id, message: .string("hi"), messageType: .send))
        package.setWebsocketMessagePackage(package: WebsocketMessagePackage(id: package.id, message: .string("bye"), messageType: .receive))
        let entry = package.harEntry()
        let messages = entry["_webSocketMessages"] as! [[String: Any]]
        XCTAssertEqual(messages.count, 2)
        for message in messages {
            XCTAssertNotNil(message["type"])
            XCTAssertNotNil(message["opcode"])
            XCTAssertNotNil(message["time"])
            XCTAssertNotNil(message["data"])
        }
    }
}

// MARK: - 2. curlCommand()

final class AtlantisCurlCommandTests: XCTestCase {

    func testGetNoHeadersNoBody() {
        let package = makePackage(method: "GET", url: "https://api.example.com/users?page=2", reqBody: nil)
        XCTAssertEqual(package.curlCommand(), "curl -X GET 'https://api.example.com/users?page=2'")
    }

    func testPostHeadersAndJSONBody() {
        let headers = [Header(key: "Content-Type", value: "application/json"),
                       Header(key: "Authorization", value: "Bearer abc123")]
        let package = makePackage(method: "POST", url: "https://api.example.com/users",
                                  reqHeaders: headers, reqBody: Data(#"{"name":"Ada","role":"admin"}"#.utf8))
        let expected = """
        curl -X POST 'https://api.example.com/users' \\
          -H 'Content-Type: application/json' \\
          -H 'Authorization: Bearer abc123' \\
          --data-binary '{"name":"Ada","role":"admin"}'
        """
        XCTAssertEqual(package.curlCommand(), expected)
    }

    func testSingleQuoteEscapingInHeaderValue() {
        let headers = [Header(key: "X-Note", value: "it's fine")]
        let package = makePackage(method: "GET", url: "https://x.test/", reqHeaders: headers, reqBody: nil)
        let expected = """
        curl -X GET 'https://x.test/' \\
          -H 'X-Note: it'\\''s fine'
        """
        XCTAssertEqual(package.curlCommand(), expected)
        XCTAssertTrue(package.curlCommand().contains("'\\''"))
    }

    func testBinaryBodyBase64InlineDecode() {
        let headers = [Header(key: "Content-Type", value: "application/octet-stream")]
        let package = makePackage(method: "POST", url: "https://x.test/upload",
                                  reqHeaders: headers, reqBody: Data([0x00, 0x01, 0x02]))
        let expected = """
        curl -X POST 'https://x.test/upload' \\
          -H 'Content-Type: application/octet-stream' \\
          --data-binary "$(echo 'AAEC' | base64 --decode)"
        """
        XCTAssertEqual(package.curlCommand(), expected)
    }

    func testEmptyBodyTreatedAsNoBody() {
        let package = makePackage(method: "POST", url: "https://x.test/", reqBody: Data())
        XCTAssertFalse(package.curlCommand().contains("--data-binary"))
    }
}

// MARK: - 3. AtlantisBodySearch

final class AtlantisBodySearchTests: XCTestCase {

    func testCaseInsensitiveMatch() {
        let ranges = AtlantisBodySearch.matchRanges(in: "Hello WORLD hello", query: "hello")
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(AtlantisBodySearch.matchCount(in: "Hello WORLD hello", query: "hello"), 2)
    }

    func testEmptyOrWhitespaceQuery() {
        XCTAssertEqual(AtlantisBodySearch.matchCount(in: "abc", query: ""), 0)
        XCTAssertEqual(AtlantisBodySearch.matchCount(in: "abc", query: "   "), 0)
    }

    func testNoOverlapDoubleCount() {
        XCTAssertEqual(AtlantisBodySearch.matchCount(in: "aaaa", query: "aa"), 2)
    }

    func testRangesAscendingAndCorrectSubstrings() {
        let text = "foo bar Foo"
        let ranges = AtlantisBodySearch.matchRanges(in: text, query: "foo")
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges.map { text[$0].lowercased() }, ["foo", "foo"])
        XCTAssertEqual(ranges, ranges.sorted { $0.lowerBound < $1.lowerBound })
    }

    func testNoMatch() {
        XCTAssertEqual(AtlantisBodySearch.matchRanges(in: "abc", query: "z"), [])
    }
}

// MARK: - 6. Views (compile / composition)

#if canImport(SwiftUI)
@available(iOS 15.0, macOS 12.0, *)
final class AtlantisTrafficListViewTests: XCTestCase {

    func testListViewConstructsWithInjectedStore() {
        let view = AtlantisTrafficListView(store: AtlantisTrafficStore())
        _ = view.body
    }

    func testListViewDefaultStoreInitializerExists() {
        let view = AtlantisTrafficListView()
        _ = view.body
    }
}

@available(iOS 15.0, macOS 12.0, *)
final class AtlantisTrafficDetailViewTests: XCTestCase {

    // 1x1 transparent PNG.
    private let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!

    func testDetailViewConstructsFromPackage() {
        let view = AtlantisTrafficDetailView(package: makePackage())
        _ = view.body
    }

    func testDetailRendersEveryBodyBranchWithoutTrapping() {
        let jsonHeaders = [Header(key: "Content-Type", value: "application/json")]
        let jsonPackage = makePackage(respHeaders: jsonHeaders, respBody: Data(#"{"a":1}"#.utf8))
        _ = AtlantisTrafficDetailView(package: jsonPackage).body

        let imageHeaders = [Header(key: "Content-Type", value: "image/png")]
        let imagePackage = makePackage(respHeaders: imageHeaders, respBody: onePixelPNG)
        _ = AtlantisTrafficDetailView(package: imagePackage).body

        let textHeaders = [Header(key: "Content-Type", value: "text/plain")]
        let textPackage = makePackage(respHeaders: textHeaders, respBody: Data("hello world".utf8))
        _ = AtlantisTrafficDetailView(package: textPackage).body

        let binaryHeaders = [Header(key: "Content-Type", value: "application/octet-stream")]
        let binaryPackage = makePackage(respHeaders: binaryHeaders, respBody: Data([0xFF, 0xD8, 0xFF, 0x00]))
        _ = AtlantisTrafficDetailView(package: binaryPackage).body

        let largeArray = (0..<2000).map { "item-\($0)-\(String(repeating: "x", count: 30))" }
        let largeBody = try! JSONSerialization.data(withJSONObject: ["items": largeArray])
        XCTAssertGreaterThan(largeBody.count, 80_000)
        let largeHeaders = [Header(key: "Content-Type", value: "application/json")]
        let largePackage = makePackage(respHeaders: largeHeaders, respBody: largeBody)
        _ = AtlantisTrafficDetailView(package: largePackage).body
    }

    func testWSDetailPath() {
        let package = makePackage(packageType: .websocket)
        package.setWebsocketMessagePackage(package: WebsocketMessagePackage(id: package.id, message: .string("hi"), messageType: .send))
        XCTAssertFalse(package.websocketMessages.isEmpty)
        _ = AtlantisTrafficDetailView(package: package).body
    }

    func testFilterAndSearchHelpersCallableFromViewLayer() {
        let packages = AtlantisTrafficFilter.apply([makePackage()], query: "", errorsOnly: false)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(AtlantisBodySearch.matchRanges(in: "abc", query: "a").count, 1)
    }
}
#endif

//
//  DemoBodyPayloads.swift
//  PortholeExample
//
//  Fires requests that exercise every body-viewer state described in
//  design/body-viewer-ui-v2.md, served locally via a fake URLProtocol so byte
//  content is exact and reproducible offline.
//

import UIKit
import Foundation

enum DemoBodyPayloads {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }()

    static func fireJSON14KB() {
        request(path: "/json-14kb")
    }

    static func fireJSON84KB() {
        request(path: "/json-84kb")
    }

    static func firePNGImage() {
        request(path: "/image-png")
    }

    static func fireInvalidUTF8Binary() {
        request(path: "/binary-invalid-utf8")
    }

    static func fireEmptyBodyGET() {
        request(path: "/empty-body")
    }

    private static func request(path: String) {
        guard let url = URL(string: "https://porthole-demo.local\(path)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        session.dataTask(with: request).resume()
    }
}

/// Serves canned responses for the `porthole-demo.local` host without touching the network,
/// so demo payload bytes are exact and available offline.
final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "porthole-demo.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, headers, body) = DemoURLProtocol.payload(for: url.path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func payload(for path: String) -> (Int, [String: String], Data?) {
        switch path {
        case "/json-14kb":
            return (200, ["Content-Type": "application/json"], jsonPayload(targetBytes: 14_000))
        case "/json-84kb":
            return (200, ["Content-Type": "application/json"], jsonPayload(targetBytes: 84_000))
        case "/image-png":
            return (200, ["Content-Type": "image/png"], pngPayload())
        case "/binary-invalid-utf8":
            return (200, ["Content-Type": "application/octet-stream"], invalidUTF8Payload())
        case "/empty-body":
            return (200, ["Content-Type": "text/plain"], nil)
        default:
            return (404, [:], nil)
        }
    }

    /// Repeats a JSON record array until the minified body reaches `targetBytes`, so the
    /// pretty/search state (14 KB) and the large-body gate (84 KB) get exact, reproducible sizes.
    private static func jsonPayload(targetBytes: Int) -> Data {
        var records: [[String: Any]] = []
        var current = 2 // account for "[]"
        var index = 0
        while current < targetBytes {
            let record: [String: Any] = [
                "id": index,
                "name": "Widget \(index)",
                "description": "A sample widget used to pad the response body for demo purposes.",
                "price": Double(index) * 1.5,
                "inStock": index % 2 == 0,
                "tags": ["demo", "widget", "porthole"],
            ]
            records.append(record)
            if let recordData = try? JSONSerialization.data(withJSONObject: record) {
                current += recordData.count + 1 // + comma
            }
            index += 1
        }
        return (try? JSONSerialization.data(withJSONObject: records)) ?? Data("[]".utf8)
    }

    private static func pngPayload() -> Data {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 128, y: 128, width: 256, height: 256))
        }
        return image.pngData() ?? Data()
    }

    /// First 4 bytes are valid ASCII; byte at offset 4 is an invalid UTF-8 lead byte, triggering
    /// the hex-dump + "invalid UTF-8" banner state.
    private static func invalidUTF8Payload() -> Data {
        var bytes: [UInt8] = Array("PORT".utf8) // valid UTF-8, offset 0-3
        bytes.append(0xFF) // invalid UTF-8 byte at offset 4
        bytes.append(contentsOf: (0..<256).map { UInt8($0 % 256) })
        return Data(bytes)
    }
}

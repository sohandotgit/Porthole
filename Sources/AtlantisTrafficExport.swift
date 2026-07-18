//
//  AtlantisTrafficExport.swift
//  atlantis
//

import Foundation

private let harDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

private func harBody(_ data: Data?, contentType: String?) -> [String: Any]? {
    guard let data = data, !data.isEmpty else { return nil }
    var body: [String: Any] = ["mimeType": contentType ?? "application/octet-stream"]
    if let text = String(data: data, encoding: .utf8) {
        body["text"] = text
    } else {
        body["text"] = data.base64EncodedString()
        body["encoding"] = "base64"
    }
    return body
}

private func harContentType(from headers: [Header]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
}

public extension TrafficPackage {

    /// One HAR 1.2 `entries[]` object.
    func harEntry() -> [String: Any] {
        let requestContentType = harContentType(from: request.headers)
        let responseContentType = response.map { harContentType(from: $0.headers) } ?? nil

        var queryString: [[String: Any]] = []
        if let items = URLComponents(string: request.url)?.queryItems {
            queryString = items.map { ["name": $0.name, "value": $0.value ?? ""] }
        }

        var requestDict: [String: Any] = [
            "method": request.method,
            "url": request.url,
            "httpVersion": "HTTP/1.1",
            "headers": request.headers.map { ["name": $0.key, "value": $0.value] },
            "queryString": queryString,
            "cookies": [],
            "headersSize": -1,
            "bodySize": request.body?.count ?? 0
        ]
        if let postData = harBody(request.body, contentType: requestContentType) {
            requestDict["postData"] = postData
        }

        let statusText: String
        if let statusCode = response?.statusCode {
            statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        } else {
            statusText = ""
        }

        let contentBody = harBody(responseBodyData, contentType: responseContentType)
            ?? ["mimeType": responseContentType ?? "application/octet-stream", "text": ""]
        var content = contentBody
        content["size"] = responseBodyData.count

        let responseDict: [String: Any] = [
            "status": response?.statusCode ?? 0,
            "statusText": statusText,
            "httpVersion": "HTTP/1.1",
            "headers": (response?.headers ?? []).map { ["name": $0.key, "value": $0.value] },
            "cookies": [],
            "content": content,
            "redirectURL": "",
            "headersSize": -1,
            "bodySize": responseBodyData.count
        ]

        let timeMs = endAt.map { ($0 - startAt) * 1000 } ?? 0

        var entry: [String: Any] = [
            "startedDateTime": harDateFormatter.string(from: Date(timeIntervalSince1970: startAt)),
            "time": timeMs,
            "request": requestDict,
            "response": responseDict,
            "cache": [:],
            "timings": ["send": 0 as Int, "wait": timeMs as Double, "receive": 0 as Int] as [String: Any]
        ]

        if packageType == .websocket, !websocketMessages.isEmpty {
            entry["_webSocketMessages"] = websocketMessages.map { message -> [String: Any] in
                let opcode = message.dataValue != nil ? "binary" : "text"
                let data: String
                if let string = message.stringValue {
                    data = string
                } else {
                    data = message.dataValue?.base64EncodedString() ?? ""
                }
                return [
                    "type": message.messageType.rawValue,
                    "opcode": opcode,
                    "time": harDateFormatter.string(from: Date(timeIntervalSince1970: message.createdAt)),
                    "data": data
                ]
            }
        }

        return entry
    }
}

public extension AtlantisTrafficStore {

    /// Complete HAR 1.2 document (`{ "log": { … } }`) as UTF-8 JSON `Data`.
    func exportHAR() -> Data {
        let log: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "Atlantis", "version": Atlantis.buildVersion],
                "entries": packages.map { $0.harEntry() }
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

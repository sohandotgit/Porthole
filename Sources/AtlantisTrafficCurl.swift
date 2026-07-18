//
//  AtlantisTrafficCurl.swift
//  atlantis
//

import Foundation

private func curlEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "'\\''")
}

/// A NUL byte can round-trip through `String(data:encoding:.utf8)` yet still marks
/// the payload as binary (e.g. `Data([0x00, 0x01, 0x02])`), so text detection also
/// rejects embedded NULs.
private func textValue(of data: Data) -> String? {
    guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
    return text
}

public extension TrafficPackage {

    /// Reproducible cURL for the request. Exact format pinned in design/viewer-api.md §3.
    func curlCommand() -> String {
        var parts: [String] = ["curl -X \(request.method) '\(curlEscape(request.url))'"]

        for header in request.headers {
            parts.append("-H '\(curlEscape(header.key)): \(curlEscape(header.value))'")
        }

        if let body = request.body, !body.isEmpty {
            if let text = textValue(of: body) {
                parts.append("--data-binary '\(curlEscape(text))'")
            } else {
                parts.append("--data-binary \"$(echo '\(body.base64EncodedString())' | base64 --decode)\"")
            }
        }

        return parts.joined(separator: " \\\n  ")
    }

    /// Request body as text (UTF-8) or, if non-text, base64. `nil` when no body.
    func requestBodyForCopy() -> String? {
        guard let body = request.body, !body.isEmpty else { return nil }
        return textValue(of: body) ?? body.base64EncodedString()
    }

    /// Response body as text (UTF-8) or, if non-text, base64. `nil` when empty.
    func responseBodyForCopy() -> String? {
        guard !responseBodyData.isEmpty else { return nil }
        return textValue(of: responseBodyData) ?? responseBodyData.base64EncodedString()
    }
}

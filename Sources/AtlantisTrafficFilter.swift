//
//  AtlantisTrafficFilter.swift
//  atlantis
//

import Foundation

/// Case-insensitive substring/errors-only filter for the traffic list. Pure and
/// UI-free so it is shared by the view and the headless test target.
public enum AtlantisTrafficFilter {

    /// Case-insensitive substring match of `query` against URL, path, method, and
    /// status code; plus an errors-only gate. Empty query matches everything.
    public static func matches(_ package: TrafficPackage,
                               query: String,
                               errorsOnly: Bool) -> Bool {
        if errorsOnly {
            let isError = (package.response?.statusCode ?? 0) >= 400 || package.error != nil
            guard isError else { return false }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let url = package.request.url
        let path = URLComponents(string: url)?.path ?? url
        let method = package.request.method
        let status = package.response.map { String($0.statusCode) } ?? ""

        return url.localizedCaseInsensitiveContains(trimmed)
            || path.localizedCaseInsensitiveContains(trimmed)
            || method.localizedCaseInsensitiveContains(trimmed)
            || status.localizedCaseInsensitiveContains(trimmed)
    }

    /// `matches` applied over `packages`, preserving order.
    public static func apply(_ packages: [TrafficPackage],
                             query: String,
                             errorsOnly: Bool) -> [TrafficPackage] {
        packages.filter { matches($0, query: query, errorsOnly: errorsOnly) }
    }
}

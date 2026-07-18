//
//  AtlantisTrafficStore.swift
//  atlantis
//

import Foundation

/// In-app, observable store of captured traffic. Fed unconditionally by both the
/// HTTP and WS/SSE send paths on the main thread. See design/capture-refactor.md.
public final class AtlantisTrafficStore: ObservableObject {

    @Published public private(set) var packages: [TrafficPackage] = []

    /// Max rows retained; oldest packages are evicted once exceeded.
    public var capacity: Int = 500

    @Published public var isPaused: Bool = false

    private var indexById: [String: Int] = [:]

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    /// Insert-by-id if new; no-op for an id already present (the underlying
    /// TrafficPackage is a class, so in-place mutations are already reflected).
    public func upsert(_ package: TrafficPackage) {
        guard !isPaused else { return }
        guard indexById[package.id] == nil else { return }
        packages.append(package)
        indexById[package.id] = packages.count - 1
        trimIfNeeded()
    }

    public func clear() {
        packages.removeAll()
        indexById.removeAll()
    }

    /// Remove a package by identity (e.g. swipe-to-delete). Reindexes remaining rows.
    public func remove(_ package: TrafficPackage) {
        guard let index = indexById[package.id] else { return }
        packages.remove(at: index)
        indexById.removeAll(keepingCapacity: true)
        for (i, package) in packages.enumerated() {
            indexById[package.id] = i
        }
    }

    private func trimIfNeeded() {
        guard packages.count > capacity else { return }
        packages.removeFirst(packages.count - capacity)
        indexById.removeAll(keepingCapacity: true)
        for (i, package) in packages.enumerated() {
            indexById[package.id] = i
        }
    }
}

//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import ObjectiveC

public protocol AtlantisDelegate: AnyObject {

    func atlantisDidHaveNewPackage(_ package: TrafficPackage)
}

/// The main class of Atlantis
/// Responsible to swizzle certain functions from URLSession
/// to capture the network and send to Proxyman app via Bonjour Service
public final class Atlantis: NSObject {

    static let shared = Atlantis()

    /// Shared in-app traffic store, observable by SwiftUI viewers.
    public static let trafficStore = AtlantisTrafficStore()

    // MARK: - Components

    private weak var delegate: AtlantisDelegate?
    private var injector: Injector = NetworkInjector()
    private(set) var configuration: Configuration = Configuration.default()
    private var packages: [String: TrafficPackage] = [:]
    private lazy var waitingWebsocketPackages: [String: [TrafficPackage]] = [:]
    private var sentServerSentEventTrafficIds: Set<String> = []
    private var serverSentEventBuffers: [String: String] = [:]
    private var ignoreProtocols: [AnyClass] = []
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")
    private var ignoredRequestIds: Set<String> = []

    // MARK: - Variables

    /// Determine whether or not the Atlantis is active
    /// It must be wrapped into an atomic for safe-threads
    private static var isEnabled = Atomic<Bool>(false)

    /// Determine if Atlantis is running on Swift Playground
    /// If it's enabled, Atlantis will bypass some safety checks
    private var isRunningOniOSPlayground = false

    private var taskStartTimes: [String: TimeInterval] = [:]
    
    // MARK: - Init

    private override init() {
        super.init()
        injector.delegate = self
    }
    
    // MARK: - Public

    /// Build version of Atlantis
    /// It's essential for Proxyman to known if it's compatible with this version
    /// Instead of receving the number from the info.plist, we should hardcode here because the info file doesn't exist in SPM
    public static let buildVersion: String = "1.36.0"

    /// Start Swizzle all network functions and monitoring the traffic
    /// - Parameter shouldCaptureWebSocketTraffic: Determine if Atlantis should perform the Method Swizzling on WS/WSS connection. Default is true.
    @objc public class func start(shouldCaptureWebSocketTraffic: Bool = true) {
        // save config
        let configuration = Configuration.default()

        guard !isEnabled.value else { return }
        isEnabled.mutate { $0 = true }

        // Enable the injector
        Atlantis.shared.configuration = configuration
        Atlantis.shared.injector.injectAllNetworkClasses(config: NetworkConfiguration(shouldCaptureWebSocketTraffic: shouldCaptureWebSocketTraffic))
    }

    /// Stop monitoring
    @objc public class func stop() {
        guard isEnabled.value else { return }
        isEnabled.mutate { $0 = false }
    }

    /// Enable Swift Playground mode
    public class func setIsRunningOniOSPlayground(_ isEnabled: Bool) {
        Atlantis.shared.isRunningOniOSPlayground = isEnabled
    }

    /// Set delegate to observe the traffic
    public class func setDelegate(_ delegate: AtlantisDelegate) {
        Atlantis.shared.delegate = delegate
    }
    
    /// Set list of URLProtocol classes that cause the duplicate records
    public class func setIgnoreProtocols(_ protocols: [AnyClass]) {
        Atlantis.shared.ignoreProtocols = protocols
    }
}

// MARK: - Private

extension Atlantis {

    private func checkShouldIgnoreByURLProtocol(protocols: [AnyClass], on request: URLRequest) -> Bool {
        // Get the BBHTTPProtocolHandler class by name
        for cls in protocols {
            
            // Get the canInitWithRequest: selector
            let selector = NSSelectorFromString("canInitWithRequest:")
            
            // Ensure the class responds to the selector
            guard let method = class_getClassMethod(cls, selector) else {
                print("[Atlantis] ❓ Warn: canInitWithRequest: method not found.")
                return false
            }
            
            // Cast the method implementation to the correct function signature
            typealias CanInitWithRequestFunction = @convention(c) (AnyClass, Selector, URLRequest) -> Bool
            let canInitWithRequest = unsafeBitCast(method_getImplementation(method), to: CanInitWithRequestFunction.self)
            
            // Call the method with the request
            if canInitWithRequest(cls, selector, request) {
                return true
            }
        }
        return false
    }

    private func getPackage(_ taskOrConnection: AnyObject, isCompleted: Bool = false) -> TrafficPackage? {
        // This method should be called from our queue
        // Receive package from the cache
        let id = PackageIdentifier.getID(taskOrConnection: taskOrConnection)

        //
        if ignoredRequestIds.contains(id) {
            if isCompleted {
                ignoredRequestIds.remove(id)
            }
            return nil
        }

        // find the package
        if let package = packages[id] {
            return package
        }

        // If not found, just generate and cache
        switch taskOrConnection {
        case let task as URLSessionTask:
            guard let request = task.currentRequestSafe,
                  let package = TrafficPackage.buildRequest(sessionTask: task, id: id) else {
                print("[Atlantis] ❌ Error: Should build package from URLSessionTask")
                return nil
            }
            
            // Just check ignore protocols if it's not empty and the session resumes the task has this protocol
            var sessionProtocols: [AnyClass] = []
            if !ignoreProtocols.isEmpty, let session = task.value(forKey: "session") as? URLSession {
                let protocols = Set((session.configuration.protocolClasses ?? []).map { NSStringFromClass($0) })
                let shouldIgnores = Set(ignoreProtocols.map { NSStringFromClass($0) })
                sessionProtocols = protocols.intersection(shouldIgnores).compactMap { NSClassFromString($0) }
            }
            
            // check should ignore this request because it's duplicated by URLProtocol classes
            if checkShouldIgnoreByURLProtocol(protocols: sessionProtocols, on: request) {
                ignoredRequestIds.insert(id)
                return nil
            }
            
            packages[id] = package
            return package
        default:
            print("[Atlantis] ❌ Error: Do not support new Type \(String(describing: taskOrConnection.className))")
        }
        return nil
    }
}

// MARK: - Injection Methods

extension Atlantis: InjectorDelegate {

    func injectorSessionDidCallResume(task: URLSessionTask) {
        // Use sync to prevent task.currentRequest.httpBody is nil
        // If we use async, sometime the httpbody is released -> Atlantis could get the Request's body
        // It's safe to use sync here because URL has their own background queue
        queue.sync {
            // store the start time, but don't create a Request here
            // because the request might not be available yet, or missing some data
            // https://github.com/ProxymanApp/atlantis/issues/177
            let id = PackageIdentifier.getID(taskOrConnection: task)
            if taskStartTimes[id] == nil {
                taskStartTimes[id] = Date().timeIntervalSince1970
            }
        }
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            let package = getPackage(dataTask)

            // should update the start time with the actual start time (from the resume() is called)
            let id = PackageIdentifier.getID(taskOrConnection: dataTask)
            if let startedAt = taskStartTimes[id] {
                package?.updateStartTime(startedAt)
            }

            // update the response
            package?.updateResponse(response)

            if let package = package, package.isServerSentEventStream {
                startSendingServerSentEventTrafficIfNeeded(package)
            }
        }
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            let package = getPackage(dataTask)
            guard let package = package else { return }

            if package.isServerSentEventStream {
                sendServerSentEventMessages(package: package, data: data)
            } else {
                package.appendResponseData(data)
            }
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        handleDidFinish(task, error: error)
    }

    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }

            // Generate new request and add the data
            let package = getPackage(task)
            if let data = data {
                package?.appendRequestData(data)
            }
        }
    }
}

// MARK: - Websocket

extension Atlantis {

    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask) {
        let message = URLSessionWebSocketTask.Message.string("ping")
        sendWebSocketMessage(task: task, messageType: .pingPong, message: message)
    }

    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        sendWebSocketMessage(task: task, messageType: .receive, message: message)
    }

    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        sendWebSocketMessage(task: task, messageType: .send, message: message)
    }

    private func sendWebSocketMessage(task: URLSessionTask, messageType: WebsocketMessagePackage.MessageType, message: URLSessionWebSocketTask.Message) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }
            prepareAndSendWSMessage(task: task) { (id) -> WebsocketMessagePackage? in
                guard let atlantisMessage = WebsocketMessagePackage.Message(message: message) else {
                    return nil
                }
                return WebsocketMessagePackage(id: id, message: atlantisMessage, messageType: messageType)
            }
        }
    }

    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }
            prepareAndSendWSMessage(task: task) { (id) -> WebsocketMessagePackage? in
                return WebsocketMessagePackage(id: id, closeCode: closeCode.rawValue, reason: reason)
            }

            // Remove after the WS connection is closed
            let id = PackageIdentifier.getID(taskOrConnection: task)
            packages.removeValue(forKey: id)
            // Clean up taskStartTimes for closed WebSocket connections
            taskStartTimes.removeValue(forKey: id)
        }
    }

    private func prepareAndSendWSMessage(task: URLSessionTask, wsPackageBuilder: (String) -> WebsocketMessagePackage?) {
        // Get the ID
        let id = PackageIdentifier.getID(taskOrConnection: task)

        // The value should be available
        if let package = packages[id] {

            // Build a package
            guard let wsPackage = wsPackageBuilder(id) else {
                print("[Atlantis][Error] Skipping sending WS Packages!! Please contact Proxyman Team.")
                return
            }

            // It's important to set a message with a WS package
            package.setWebsocketMessagePackage(package: wsPackage)

            // Sending via Bonjour service
            startSendingWebsocketMessage(package)
        }
    }
}

// MARK: - Private

extension Atlantis {

    private func handleDidFinish(_ taskOrConnection: AnyObject, error: Error?) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            guard let package = getPackage(taskOrConnection, isCompleted: true) else {
                return
            }

            // All done
            package.updateDidComplete(error)

            if package.isServerSentEventStream {
                sendServerSentEventCloseMessage(package: package, error: error)
                removeCompletedPackage(taskOrConnection: taskOrConnection, package: package)
                return
            }

            // At this time, the package has all the data
            // It's time to send it
            startSendingMessage(package: package)

            // Then remove it from our cache
            switch package.packageType {
            case .http:
                removeCompletedPackage(taskOrConnection: taskOrConnection, package: package)
            case .websocket:
                // Don't remove the WS traffic
                // Keep it in the packages, so we can send the WS Message
                // Only remove the we receive the Close message

                // Sending all waiting WS
                attemptSendingAllWaitingWSPackages(id: package.id)
                // Clean up taskStartTimes for completed WebSocket requests
                let taskId = PackageIdentifier.getID(taskOrConnection: taskOrConnection)
                taskStartTimes.removeValue(forKey: taskId)
                break
            }
        }
    }

    /// Feed the in-app store + delegate, unconditionally, on the main thread.
    private func notifyStoreAndDelegate(_ package: TrafficPackage) {
        DispatchQueue.main.async {
            Atlantis.trafficStore.upsert(package)
            self.delegate?.atlantisDidHaveNewPackage(package)
        }
    }

    func startSendingMessage(package: TrafficPackage) {
        notifyStoreAndDelegate(package)
    }

    func startSendingWebsocketMessage(_ package: TrafficPackage) {
        let id = package.id

        // If the response of WS is nil
        // It means that the WS is not finished yet,
        // We don't send it, we put it in the waiting queue
        if package.response == nil {
            var waitingList = waitingWebsocketPackages[id] ?? []
            waitingList.append(package)
            waitingWebsocketPackages[id] = waitingList
            return
        }

        // Sending all waiting WS if need
        attemptSendingAllWaitingWSPackages(id: id)

        // Send the current one
        notifyStoreAndDelegate(package)
    }

    private func attemptSendingAllWaitingWSPackages(id: String) {
        guard !waitingWebsocketPackages.isEmpty else {
            return
        }
        guard let waitingList = waitingWebsocketPackages[id] else {
            return
        }

        // Send all waiting WS Message
        waitingList.forEach { item in
            notifyStoreAndDelegate(item)
        }

        // Release the list
        waitingWebsocketPackages[id] = nil
    }

    private func removeCompletedPackage(taskOrConnection: AnyObject, package: TrafficPackage) {
        let taskId = PackageIdentifier.getID(taskOrConnection: taskOrConnection)
        packages.removeValue(forKey: package.id)
        taskStartTimes.removeValue(forKey: taskId)
        sentServerSentEventTrafficIds.remove(package.id)
        serverSentEventBuffers.removeValue(forKey: package.id)
    }
}

// MARK: - Server-Sent Events

extension Atlantis {

    private func startSendingServerSentEventTrafficIfNeeded(_ package: TrafficPackage) {
        guard !sentServerSentEventTrafficIds.contains(package.id) else {
            return
        }
        sentServerSentEventTrafficIds.insert(package.id)
        package.markAsWebsocketPackage()
        startSendingMessage(package: package)
    }

    private func sendServerSentEventMessages(package: TrafficPackage, data: Data) {
        startSendingServerSentEventTrafficIfNeeded(package)

        for eventText in parseServerSentEventBlocks(packageId: package.id, data: data) {
            sendServerSentEventMessage(package: package, eventText: eventText)
        }
    }

    private func sendServerSentEventMessage(package: TrafficPackage, eventText: String) {
        let normalizedEventText = eventText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Reuse Proxyman's streaming-message channel so each SSE event is appended
        // to the original request instead of creating another traffic row.
        let streamMessage = WebsocketMessagePackage(id: package.id,
                                                    message: .string(normalizedEventText),
                                                    messageType: .receive)
        package.setWebsocketMessagePackage(package: streamMessage)
        startSendingWebsocketMessage(package)
    }

    private func sendServerSentEventCloseMessage(package: TrafficPackage, error: Error?) {
        guard sentServerSentEventTrafficIds.contains(package.id) else {
            return
        }

        if let pendingEvent = serverSentEventBuffers[package.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pendingEvent.isEmpty {
            sendServerSentEventMessage(package: package, eventText: pendingEvent)
        }

        let reason = error?.localizedDescription.data(using: .utf8)
        let closeMessage = WebsocketMessagePackage(id: package.id,
                                                   closeCode: URLSessionWebSocketTask.CloseCode.normalClosure.rawValue,
                                                   reason: reason)
        package.setWebsocketMessagePackage(package: closeMessage)
        startSendingWebsocketMessage(package)
    }

    private func parseServerSentEventBlocks(packageId: String, data: Data) -> [String] {
        let chunk = String(decoding: data, as: UTF8.self)
        var buffer = (serverSentEventBuffers[packageId] ?? "") + chunk
        var events: [String] = []

        while let delimiterRange = firstServerSentEventDelimiterRange(in: buffer) {
            let eventText = String(buffer[..<delimiterRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<delimiterRange.upperBound)

            if !eventText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                events.append(eventText)
            }
        }

        serverSentEventBuffers[packageId] = buffer
        return events
    }

    private func firstServerSentEventDelimiterRange(in text: String) -> Range<String.Index>? {
        let delimiters = ["\r\n\r\n", "\n\n", "\r\r"]
        return delimiters
            .compactMap { text.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }
}

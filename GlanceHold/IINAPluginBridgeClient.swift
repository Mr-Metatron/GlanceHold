import Foundation

enum IINAPluginBridgeClientError: Error, Equatable {
    case pluginNeeded
    case unavailable
    case malformedResponse
    case requestMismatch
    case commandFailed(String)
}

protocol IINAPluginBridgeTransporting {
    func roundTrip(
        _ message: String,
        timeout: TimeInterval,
        ignoring shouldIgnore: @escaping (String) -> Bool
    ) async throws -> String
    func messages(timeout: TimeInterval) -> AsyncThrowingStream<String, Error>
}

extension IINAPluginBridgeTransporting {
    func roundTrip(_ message: String, timeout: TimeInterval) async throws -> String {
        try await roundTrip(message, timeout: timeout, ignoring: { _ in false })
    }
}

protocol IINAPluginBridgeClienting {
    func status() async -> IINAPlayerStatus
    func pushedEvents() -> AsyncStream<IINAPluginBridgePushedEvent>
    func statusUpdates() -> AsyncStream<IINAPlayerStatus>
    func monitoringToggleRequests() -> AsyncStream<Void>
    func execute(_ intent: PlaybackIntent) async throws
}

extension IINAPluginBridgeClienting {
    func pushedEvents() -> AsyncStream<IINAPluginBridgePushedEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await status in statusUpdates() {
                    if Task.isCancelled {
                        break
                    }
                    continuation.yield(.status(status))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func monitoringToggleRequests() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

enum IINAPluginBridgePushedEvent: Equatable {
    case status(IINAPlayerStatus)
    case heartbeat
}

struct IINAPluginBridgeTokenStore {
    private static let tokenKey = "iinaPluginBridgeToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadOrCreateToken() -> String {
        if let token = defaults.string(forKey: Self.tokenKey), Self.isValid(token) {
            return token
        }

        let token = Self.makeToken()
        defaults.set(token, forKey: Self.tokenKey)
        return token
    }

    private static func makeToken() -> String {
        [UUID().uuidString, UUID().uuidString]
            .joined(separator: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func isValid(_ token: String) -> Bool {
        token.count >= 32 && token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

final class IINAPluginBridgeClient: IINAPluginBridgeClienting {
    private struct Request: Encodable {
        var id: Int
        var version: Int
        var token: String
        var type: String
        var command: String?
        var speed: Double?
    }

    private struct Response: Decodable {
        var id: Int?
        var version: Int?
        var ok: Bool
        var snapshot: Snapshot?
        var error: String?
    }

    private struct StatusChanged: Decodable {
        var id: Int?
        var version: Int
        var type: String
        var snapshot: Snapshot
    }

    private struct PushedEvent: Decodable {
        var id: Int?
        var version: Int
        var type: String
    }

    private struct Heartbeat: Decodable {
        var id: Int?
        var version: Int
        var type: String
        var snapshot: Snapshot?
    }

    private struct Snapshot: Decodable {
        var state: String
        var speed: Double?
    }

    private static let protocolVersion = 1

    private let transport: IINAPluginBridgeTransporting
    private let timeout: TimeInterval
    private let streamStaleTimeout: TimeInterval
    private let bridgeToken: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let requestIDLock = NSLock()
    private var nextRequestID = 1

    init(
        url: URL = URL(string: "ws://127.0.0.1:47873")!,
        transport: IINAPluginBridgeTransporting? = nil,
        bridgeToken: String? = nil,
        tokenStore: IINAPluginBridgeTokenStore = IINAPluginBridgeTokenStore(),
        timeout: TimeInterval = 1.0,
        streamStaleTimeout: TimeInterval = 15.0
    ) {
        self.transport = transport ?? URLSessionIINAPluginBridgeTransport(url: url)
        self.timeout = timeout
        self.streamStaleTimeout = streamStaleTimeout
        self.bridgeToken = bridgeToken ?? tokenStore.loadOrCreateToken()
    }

    func status() async -> IINAPlayerStatus {
        do {
            return try await snapshot()
        } catch IINAPluginBridgeClientError.pluginNeeded {
            return .setupNeeded
        } catch {
            return .unavailable
        }
    }

    func snapshot() async throws -> IINAPlayerStatus {
        let request = Request(
            id: nextID(),
            version: Self.protocolVersion,
            token: bridgeToken,
            type: "snapshot",
            command: nil,
            speed: nil
        )
        let response = try await send(request)
        guard let snapshot = response.snapshot else {
            throw IINAPluginBridgeClientError.malformedResponse
        }

        return try status(from: snapshot)
    }

    func statusUpdates() -> AsyncStream<IINAPlayerStatus> {
        AsyncStream { continuation in
            let task = Task {
                for await event in pushedEvents() {
                    if Task.isCancelled {
                        break
                    }

                    guard case let .status(status) = event else {
                        continue
                    }
                    continuation.yield(status)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func pushedEvents() -> AsyncStream<IINAPluginBridgePushedEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await message in transport.messages(timeout: streamStaleTimeout) {
                        if Task.isCancelled {
                            break
                        }

                        guard let event = decodePushedEvent(message) else {
                            continue
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch IINAPluginBridgeClientError.pluginNeeded {
                    continuation.yield(.status(.setupNeeded))
                    continuation.finish()
                } catch {
                    continuation.yield(.status(.unavailable))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func monitoringToggleRequests() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await message in transport.messages(timeout: streamStaleTimeout) {
                        if Task.isCancelled {
                            break
                        }

                        guard decodeMonitoringToggleRequested(message) else {
                            continue
                        }
                        continuation.yield(())
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        guard let request = request(for: intent) else {
            return
        }

        _ = try await send(request)
    }

    private func decodePushedEvent(_ message: String) -> IINAPluginBridgePushedEvent? {
        if let status = decodeStatusChanged(message) {
            return .status(status)
        }

        if decodeHeartbeat(message) {
            return .heartbeat
        }

        return nil
    }

    private func decodeStatusChanged(_ message: String) -> IINAPlayerStatus? {
        guard let data = message.data(using: .utf8),
              let event = try? decoder.decode(StatusChanged.self, from: data),
              event.id == nil,
              event.version == Self.protocolVersion,
              event.type == "statusChanged" else {
            return nil
        }

        return try? status(from: event.snapshot)
    }

    private func decodeHeartbeat(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let event = try? decoder.decode(Heartbeat.self, from: data) else {
            return false
        }

        return event.id == nil
            && event.version == Self.protocolVersion
            && event.type == "heartbeat"
            && event.snapshot == nil
    }

    private func decodeMonitoringToggleRequested(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let event = try? decoder.decode(PushedEvent.self, from: data) else {
            return false
        }

        return event.id == nil
            && event.version == Self.protocolVersion
            && event.type == "toggleMonitoringRequested"
    }

    private func status(from snapshot: Snapshot) throws -> IINAPlayerStatus {
        switch snapshot.state {
        case "playing":
            guard let speed = finiteSpeed(snapshot.speed) else {
                throw IINAPluginBridgeClientError.unavailable
            }
            return .playing(speed: speed)
        case "paused":
            guard let speed = finiteSpeed(snapshot.speed) else {
                throw IINAPluginBridgeClientError.unavailable
            }
            return .paused(speed: speed)
        case "idle":
            return .idle
        default:
            throw IINAPluginBridgeClientError.unavailable
        }
    }

    private func request(for intent: PlaybackIntent) -> Request? {
        let id = nextID()
        switch intent {
        case .holdSpeedAtOne:
            return Request(id: id, version: Self.protocolVersion, token: bridgeToken, type: "command", command: "setSpeed", speed: 1.0)
        case let .restoreSpeed(speed):
            return Request(id: id, version: Self.protocolVersion, token: bridgeToken, type: "command", command: "setSpeed", speed: speed)
        case .pause:
            return Request(id: id, version: Self.protocolVersion, token: bridgeToken, type: "command", command: "pause", speed: nil)
        case .resume:
            return Request(id: id, version: Self.protocolVersion, token: bridgeToken, type: "command", command: "resume", speed: nil)
        case .stopMonitoring:
            return nil
        }
    }

    private func send(_ request: Request) async throws -> Response {
        let data = try encoder.encode(request)
        guard let message = String(data: data, encoding: .utf8) else {
            throw IINAPluginBridgeClientError.malformedResponse
        }

        let responseText: String
        do {
            responseText = try await transport.roundTrip(
                message,
                timeout: timeout,
                ignoring: shouldIgnoreRequestPathMessage(_:)
            )
        } catch let error as IINAPluginBridgeClientError {
            throw error
        } catch {
            throw IINAPluginBridgeClientError.unavailable
        }

        guard let responseData = responseText.data(using: .utf8),
              let response = try? decoder.decode(Response.self, from: responseData) else {
            throw IINAPluginBridgeClientError.malformedResponse
        }

        guard response.id == request.id, response.version == Self.protocolVersion else {
            throw IINAPluginBridgeClientError.requestMismatch
        }

        guard response.ok else {
            let message = response.error ?? "unavailable"
            if message == "unavailable" {
                throw IINAPluginBridgeClientError.unavailable
            }
            throw IINAPluginBridgeClientError.commandFailed(message)
        }

        return response
    }

    private func shouldIgnoreRequestPathMessage(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let event = try? decoder.decode(PushedEvent.self, from: data) else {
            return false
        }

        return event.id == nil
            && event.version == Self.protocolVersion
            && (event.type == "statusChanged" || event.type == "toggleMonitoringRequested" || decodeHeartbeat(message))
    }

    private func nextID() -> Int {
        requestIDLock.lock()
        defer { requestIDLock.unlock() }

        let id = nextRequestID
        nextRequestID += 1
        return id
    }

    private func finiteSpeed(_ speed: Double?) -> Double? {
        guard let speed, speed.isFinite else {
            return nil
        }
        return speed
    }
}

struct URLSessionIINAPluginBridgeTransport: IINAPluginBridgeTransporting {
    private let url: URL
    private let session: URLSession

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func roundTrip(
        _ message: String,
        timeout: TimeInterval,
        ignoring shouldIgnore: @escaping (String) -> Bool
    ) async throws -> String {
        let task = session.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await send(message, using: task)
                    while true {
                        let response = try await receive(from: task)
                        if shouldIgnore(response) {
                            continue
                        }
                        return response
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw IINAPluginBridgeClientError.pluginNeeded
                }

                guard let result = try await group.next() else {
                    throw IINAPluginBridgeClientError.unavailable
                }
                group.cancelAll()
                return result
            }
        } catch let error as IINAPluginBridgeClientError {
            throw error
        } catch {
            throw mapURLSessionError(error)
        }
    }

    func messages(timeout: TimeInterval) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = session.webSocketTask(with: url)
            task.resume()

            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await receive(from: task, timeout: timeout)
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch let error as IINAPluginBridgeClientError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: mapURLSessionError(error))
                }
            }

            continuation.onTermination = { _ in
                receiveTask.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func send(_ message: String, using task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(.string(message)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func receive(from task: URLSessionWebSocketTask) async throws -> String {
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw IINAPluginBridgeClientError.malformedResponse
            }
            return text
        @unknown default:
            throw IINAPluginBridgeClientError.malformedResponse
        }
    }

    private func receive(from task: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await receive(from: task)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw IINAPluginBridgeClientError.pluginNeeded
            }

            guard let result = try await group.next() else {
                throw IINAPluginBridgeClientError.unavailable
            }
            group.cancelAll()
            return result
        }
    }

    private func mapURLSessionError(_ error: Error) -> IINAPluginBridgeClientError {
        guard let urlError = error as? URLError else {
            return .unavailable
        }

        switch urlError.code {
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            return .pluginNeeded
        default:
            return .unavailable
        }
    }
}

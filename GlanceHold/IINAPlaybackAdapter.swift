import Foundation

enum IINAPlayerStatus: Equatable {
    case setupNeeded
    case unavailable
    case idle
    case paused(speed: Double)
    case playing(speed: Double)
}

enum IINAPlaybackStatusEvent: Equatable {
    case status(PlayerSnapshot)
    case heartbeat
}

protocol IINAPlaybackAdapting {
    func snapshot() async -> PlayerSnapshot
    func statusEvents() -> AsyncStream<IINAPlaybackStatusEvent>
    func statusUpdates() -> AsyncStream<PlayerSnapshot>
    func execute(_ intent: PlaybackIntent) async throws
}

extension IINAPlaybackAdapting {
    func statusEvents() -> AsyncStream<IINAPlaybackStatusEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await snapshot in statusUpdates() {
                    if Task.isCancelled {
                        break
                    }
                    continuation.yield(.status(snapshot))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func statusUpdates() -> AsyncStream<PlayerSnapshot> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

struct IINAPlaybackAdapter: IINAPlaybackAdapting {
    private let client: MPVJSONIPCClienting
    private let socketExists: (String) -> Bool

    init(
        client: MPVJSONIPCClienting = MPVJSONIPCClient(),
        socketExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.client = client
        self.socketExists = socketExists
    }

    func snapshot() async -> PlayerSnapshot {
        await status().playerSnapshot
    }

    func status() async -> IINAPlayerStatus {
        guard socketExists(client.socketPath) else {
            return .setupNeeded
        }

        do {
            let speed = try await client.getProperty("speed")
            let pause = try await client.getProperty("pause")
            let idle = try await client.getProperty("idle-active")

            guard idle.boolValue != true else {
                return .idle
            }

            guard let speedValue = speed.doubleValue, let isPaused = pause.boolValue else {
                return .unavailable
            }

            return isPaused ? .paused(speed: speedValue) : .playing(speed: speedValue)
        } catch {
            return .unavailable
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        switch intent {
        case .holdSpeedAtOne:
            try await client.send(command: [.string("set_property"), .string("speed"), .double(1.0)])
        case let .restoreSpeed(speed):
            try await client.send(command: [.string("set_property"), .string("speed"), .double(speed)])
        case .pause:
            try await client.send(command: [.string("set_property"), .string("pause"), .bool(true)])
        case .resume:
            try await client.send(command: [.string("set_property"), .string("pause"), .bool(false)])
        case .stopMonitoring:
            return
        }
    }
}

private extension IINAPlayerStatus {
    var playerSnapshot: PlayerSnapshot {
        switch self {
        case .setupNeeded:
            return .setupNeeded
        case .unavailable:
            return .playerUnavailable
        case .idle:
            return .idle
        case let .paused(speed):
            return .paused(speed: speed)
        case let .playing(speed):
            return .playing(speed: speed)
        }
    }
}

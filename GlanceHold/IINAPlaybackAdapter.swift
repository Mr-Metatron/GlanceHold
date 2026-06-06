import Foundation

enum IINAPlayerStatus: Equatable {
    case unavailable
    case idle
    case paused(speed: Double)
    case playing(speed: Double)
}

protocol IINAPlaybackAdapting {
    func snapshot() async -> PlayerSnapshot
    func execute(_ intent: PlaybackIntent) async throws
}

struct IINAPlaybackAdapter: IINAPlaybackAdapting {
    private let client: MPVJSONIPCClienting

    init(client: MPVJSONIPCClienting = MPVJSONIPCClient()) {
        self.client = client
    }

    func snapshot() async -> PlayerSnapshot {
        await status().playerSnapshot
    }

    func status() async -> IINAPlayerStatus {
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
        case .pause, .resume, .stopMonitoring:
            return
        }
    }
}

private extension IINAPlayerStatus {
    var playerSnapshot: PlayerSnapshot {
        switch self {
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

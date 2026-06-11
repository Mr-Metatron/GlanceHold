import Foundation

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

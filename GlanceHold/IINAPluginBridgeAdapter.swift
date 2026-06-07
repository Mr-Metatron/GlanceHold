import Foundation

struct IINAPluginBridgeAdapter: IINAPlaybackAdapting {
    private let client: IINAPluginBridgeClienting

    init(client: IINAPluginBridgeClienting = IINAPluginBridgeClient()) {
        self.client = client
    }

    func snapshot() async -> PlayerSnapshot {
        await client.status().playerSnapshot
    }

    func execute(_ intent: PlaybackIntent) async throws {
        try await client.execute(intent)
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

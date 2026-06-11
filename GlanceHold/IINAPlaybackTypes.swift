import Foundation

enum IINAPlayerStatus: Equatable {
    case setupNeeded
    case unavailable
    case pluginUpdateRequired
    case idle
    case paused(speed: Double, manualAction: PlayerManualAction? = nil)
    case playing(speed: Double, manualAction: PlayerManualAction? = nil)
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

extension IINAPlayerStatus {
    var playerSnapshot: PlayerSnapshot {
        switch self {
        case .setupNeeded:
            return .setupNeeded
        case .unavailable:
            return .playerUnavailable
        case .pluginUpdateRequired:
            return .pluginUpdateRequired
        case .idle:
            return .idle
        case let .paused(speed, manualAction):
            return PlayerSnapshot(playbackState: .paused, speed: speed, manualAction: manualAction)
        case let .playing(speed, manualAction):
            return PlayerSnapshot(playbackState: .playing, speed: speed, manualAction: manualAction)
        }
    }
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

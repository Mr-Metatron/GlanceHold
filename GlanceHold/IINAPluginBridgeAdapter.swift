import Foundation

struct IINAPluginBridgeAdapter: IINAPlaybackAdapting {
    private let client: IINAPluginBridgeClienting

    init(client: IINAPluginBridgeClienting = IINAPluginBridgeClient()) {
        self.client = client
    }

    func snapshot() async -> PlayerSnapshot {
        await client.status().playerSnapshot
    }

    func statusUpdates() -> AsyncStream<PlayerSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                for await event in statusEvents() {
                    if Task.isCancelled {
                        break
                    }

                    guard case let .status(snapshot) = event else {
                        continue
                    }
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func statusEvents() -> AsyncStream<IINAPlaybackStatusEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await event in client.pushedEvents() {
                    if Task.isCancelled {
                        break
                    }

                    switch event {
                    case let .status(status):
                        continuation.yield(.status(status.playerSnapshot))
                    case .heartbeat:
                        continuation.yield(.heartbeat)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        try await client.execute(intent)
    }
}

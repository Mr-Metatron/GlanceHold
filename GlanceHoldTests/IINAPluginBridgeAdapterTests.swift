import XCTest
@testable import GlanceHold

final class IINAPluginBridgeAdapterTests: XCTestCase {
    func testPluginBridgeSnapshotsMapToExistingPlayerSnapshots() async throws {
        let client = FakeIINAPluginBridgeClient(statuses: [
            .playing(speed: 1.5),
            .paused(speed: 1.25),
            .idle,
            .setupNeeded,
            .pluginUpdateRequired,
            .unavailable
        ])
        let adapter = IINAPluginBridgeAdapter(client: client)

        let playing = await adapter.snapshot()
        let paused = await adapter.snapshot()
        let idle = await adapter.snapshot()
        let setupNeeded = await adapter.snapshot()
        let pluginUpdateRequired = await adapter.snapshot()
        let unavailable = await adapter.snapshot()

        XCTAssertEqual(playing, .playing(speed: 1.5))
        XCTAssertEqual(paused, .paused(speed: 1.25))
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(setupNeeded, .setupNeeded)
        XCTAssertEqual(pluginUpdateRequired, .pluginUpdateRequired)
        XCTAssertEqual(unavailable, .playerUnavailable)
    }

    func testPluginBridgeStatusUpdatesMapToPlayerSnapshots() async throws {
        let client = FakeIINAPluginBridgeClient(
            statuses: [],
            updateStatuses: [
                .paused(speed: 2.0),
                .playing(speed: 2.0),
                .idle
            ]
        )
        let adapter = IINAPluginBridgeAdapter(client: client)

        var snapshots: [PlayerSnapshot] = []
        for await snapshot in adapter.statusUpdates() {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots, [
            .paused(speed: 2.0),
            .playing(speed: 2.0),
            .idle
        ])
    }

    func testPluginBridgeStatusEventsPassHeartbeatWithoutPlayerSnapshot() async throws {
        let client = FakeIINAPluginBridgeClient(
            statuses: [],
            updateEvents: [
                .heartbeat,
                .status(.pluginUpdateRequired),
                .status(.playing(speed: 2.0))
            ]
        )
        let adapter = IINAPluginBridgeAdapter(client: client)

        var events: [IINAPlaybackStatusEvent] = []
        for await event in adapter.statusEvents() {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .heartbeat,
            .status(.pluginUpdateRequired),
            .status(.playing(speed: 2.0))
        ])
    }
}

private final class FakeIINAPluginBridgeClient: IINAPluginBridgeClienting {
    private var statuses: [IINAPlayerStatus]
    private let updateEvents: [IINAPluginBridgePushedEvent]
    private(set) var commands: [PlaybackIntent] = []

    init(
        statuses: [IINAPlayerStatus],
        updateStatuses: [IINAPlayerStatus] = [],
        updateEvents: [IINAPluginBridgePushedEvent]? = nil
    ) {
        self.statuses = statuses
        self.updateEvents = updateEvents ?? updateStatuses.map { .status($0) }
    }

    func status() async -> IINAPlayerStatus {
        statuses.isEmpty ? .unavailable : statuses.removeFirst()
    }

    func statusUpdates() -> AsyncStream<IINAPlayerStatus> {
        AsyncStream { continuation in
            for event in updateEvents {
                guard case let .status(status) = event else {
                    continue
                }
                continuation.yield(status)
            }
            continuation.finish()
        }
    }

    func pushedEvents() -> AsyncStream<IINAPluginBridgePushedEvent> {
        AsyncStream { continuation in
            for event in updateEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        commands.append(intent)
    }
}

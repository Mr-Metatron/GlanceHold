import XCTest
@testable import GlanceHold

final class IINAPluginBridgeAdapterTests: XCTestCase {
    func testPluginBridgeSnapshotsMapToExistingPlayerSnapshots() async throws {
        let client = FakeIINAPluginBridgeClient(statuses: [
            .playing(speed: 1.5),
            .paused(speed: 1.25),
            .idle,
            .setupNeeded,
            .unavailable
        ])
        let adapter = IINAPluginBridgeAdapter(client: client)

        let playing = await adapter.snapshot()
        let paused = await adapter.snapshot()
        let idle = await adapter.snapshot()
        let setupNeeded = await adapter.snapshot()
        let unavailable = await adapter.snapshot()

        XCTAssertEqual(playing, .playing(speed: 1.5))
        XCTAssertEqual(paused, .paused(speed: 1.25))
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(setupNeeded, .setupNeeded)
        XCTAssertEqual(unavailable, .playerUnavailable)
    }
}

private final class FakeIINAPluginBridgeClient: IINAPluginBridgeClienting {
    private var statuses: [IINAPlayerStatus]
    private(set) var commands: [PlaybackIntent] = []

    init(statuses: [IINAPlayerStatus]) {
        self.statuses = statuses
    }

    func status() async -> IINAPlayerStatus {
        statuses.isEmpty ? .unavailable : statuses.removeFirst()
    }

    func execute(_ intent: PlaybackIntent) async throws {
        commands.append(intent)
    }
}

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

        XCTAssertEqual(await adapter.snapshot(), .playing(speed: 1.5))
        XCTAssertEqual(await adapter.snapshot(), .paused(speed: 1.25))
        XCTAssertEqual(await adapter.snapshot(), .idle)
        XCTAssertEqual(await adapter.snapshot(), .setupNeeded)
        XCTAssertEqual(await adapter.snapshot(), .playerUnavailable)
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

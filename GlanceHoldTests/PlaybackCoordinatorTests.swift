import XCTest
@testable import GlanceHold

final class PlaybackCoordinatorTests: XCTestCase {
    func testAwaySendsOneHoldSpeedCommand() async throws {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
    }

    func testRecoveryRestoresCapturedSpeedAfterFreshSnapshot() async throws {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.25),
                .playing(speed: 1.0),
                .playing(speed: 1.0),
                .playing(speed: 1.25)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne, .restoreSpeed(1.25)])
    }

    func testUnavailableIdleAndMissingSpeedSendNoCommand() async {
        let snapshots: [PlayerSnapshot] = [
            .playerUnavailable,
            .idle,
            PlayerSnapshot(playbackState: .playing, speed: nil)
        ]

        for snapshot in snapshots {
            let adapter = FakeIINAPlaybackAdapter(snapshots: [snapshot])
            let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

            await coordinator.handleAttentionState(.lookingAway)

            XCTAssertEqual(adapter.commands, [])
            XCTAssertFalse(coordinator.state.isPlayerControllable)
        }
    }

    func testEachIntentIsFollowedByConfirmationSnapshot() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.snapshotReadCount, 2)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
    }
}

final class FakeIINAPlaybackAdapter: IINAPlaybackAdapting {
    private var snapshots: [PlayerSnapshot]
    var commands: [PlaybackIntent] = []
    var failingCommands: [PlaybackIntent] = []
    private(set) var snapshotReadCount = 0

    init(snapshots: [PlayerSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> PlayerSnapshot {
        snapshotReadCount += 1

        guard !snapshots.isEmpty else {
            return .playerUnavailable
        }

        return snapshots.removeFirst()
    }

    func execute(_ intent: PlaybackIntent) async throws {
        commands.append(intent)

        if failingCommands.contains(intent) {
            throw MPVJSONIPCClientError.timeout
        }
    }
}

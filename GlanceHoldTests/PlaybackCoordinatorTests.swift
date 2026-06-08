import XCTest
@testable import GlanceHold

final class PlaybackCoordinatorTests: XCTestCase {
    func testAwaySendsOneHoldSpeedCommand() async throws {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(completedActions, [.heldSpeedAtOne])
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
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne, .restoreSpeed(1.25)])
        XCTAssertEqual(completedActions, [.heldSpeedAtOne, .restoredSpeed(1.25)])
    }

    func testFailedConfirmationDoesNotEmitCompletedPlaybackAction() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(completedActions, [])
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

    func testRefreshPlayerStateReadsSnapshotWithoutPlaybackCommand() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.refreshPlayerState()

        XCTAssertEqual(adapter.snapshotReadCount, 1)
        XCTAssertTrue(coordinator.state.isPlayerControllable)
        XCTAssertEqual(coordinator.state.playerSnapshot, .playing(speed: 1.5))
        XCTAssertEqual(adapter.commands, [])
    }

    func testRepeatedRefreshUpdatesPausedToPlayingWithoutPlaybackCommand() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.paused(speed: 2.0), .playing(speed: 2.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.refreshPlayerState()
        await coordinator.refreshPlayerState()

        XCTAssertEqual(adapter.snapshotReadCount, 2)
        XCTAssertTrue(coordinator.state.isPlayerControllable)
        XCTAssertEqual(coordinator.state.playerSnapshot, .playing(speed: 2.0))
        XCTAssertEqual(adapter.commands, [])
    }

    func testPushedSnapshotUpdatesPausedToPlayingWithoutPlaybackCommand() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        coordinator.applyPushedPlayerSnapshot(.paused(speed: 2.0))
        coordinator.applyPushedPlayerSnapshot(.playing(speed: 2.0))

        XCTAssertEqual(adapter.snapshotReadCount, 0)
        XCTAssertTrue(coordinator.state.isPlayerControllable)
        XCTAssertEqual(coordinator.state.playerSnapshot, .playing(speed: 2.0))
        XCTAssertEqual(adapter.commands, [])
    }

    func testPauseModeAwaySendsPause() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .paused(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.commands, [.pause])
        XCTAssertEqual(completedActions, [.pausedByGlanceHold])
    }

    func testPauseModeFacingResumesOnlyAfterFreshPausedSnapshot() async {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .paused(speed: 1.5),
                .paused(speed: 1.5),
                .playing(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.pause, .resume])
        XCTAssertEqual(adapter.snapshotReadCount, 4)
        XCTAssertEqual(completedActions, [.pausedByGlanceHold, .resumedPlayback])
    }

    func testManualTakeoverStopsMonitoringWithoutRestoreOrResume() async {
        let speedAdapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.75),
                .playing(speed: 1.0),
                PlayerSnapshot(playbackState: .playing, speed: 1.25, manualAction: .speedChanged)
            ]
        )
        let speedCoordinator = PlaybackCoordinator(mode: .speedControl, adapter: speedAdapter)

        await speedCoordinator.handleAttentionState(.lookingAway)
        await speedCoordinator.handleAttentionState(.facing)

        XCTAssertEqual(speedAdapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(speedCoordinator.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(speedAdapter.commands)

        let pauseAdapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .paused(speed: 1.5),
                PlayerSnapshot(playbackState: .paused, speed: 1.5, manualAction: .playPressed)
            ]
        )
        let pauseCoordinator = PlaybackCoordinator(mode: .pauseResume, adapter: pauseAdapter)

        await pauseCoordinator.handleAttentionState(.lookingAway)
        await pauseCoordinator.handleAttentionState(.facing)

        XCTAssertEqual(pauseAdapter.commands, [.pause])
        XCTAssertEqual(pauseCoordinator.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(pauseAdapter.commands)
    }

    func testManualTakeoverRequestsAppLevelMonitoringStop() async {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.75),
                .playing(speed: 1.0),
                PlayerSnapshot(playbackState: .playing, speed: 1.25, manualAction: .speedChanged)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var requestedStops: [StopMonitoringReason] = []
        coordinator.stopMonitoringRequested = { reason in
            requestedStops.append(reason)
        }

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(requestedStops, [.manualPlayerTakeover])
        XCTAssertEqual(coordinator.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testPushedManualPauseWhileMonitoringRequestsStopWithoutResume() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var requestedStops: [StopMonitoringReason] = []
        coordinator.stopMonitoringRequested = { reason in
            requestedStops.append(reason)
        }

        await coordinator.handleAttentionState(.facing)
        coordinator.applyPushedPlayerSnapshot(.paused(speed: 1.5))

        XCTAssertEqual(requestedStops, [.manualPlayerTakeover])
        XCTAssertEqual(coordinator.state.stoppedReason, .manualPlayerTakeover)
        XCTAssertEqual(adapter.commands, [])
        assertNoRestoreOrResume(adapter.commands)
    }

    func testRefreshPreservesManualTakeoverStopReason() async {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.75),
                .playing(speed: 1.0),
                PlayerSnapshot(playbackState: .playing, speed: 1.25, manualAction: .speedChanged),
                .playing(speed: 1.25)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)
        await coordinator.refreshPlayerState()

        XCTAssertEqual(coordinator.state.stoppedReason, .manualPlayerTakeover)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testStopMonitoringClearsSpeedOwnershipWithoutRestoreCommandSnapshotOrCallback() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.75), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)
        coordinator.stopMonitoring()
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(adapter.snapshotReadCount, 3)
        XCTAssertEqual(completedActions, [.heldSpeedAtOne])
        XCTAssertNil(coordinator.state.stoppedReason)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testStopMonitoringClearsPauseOwnershipWithoutResumeCommandSnapshotOrCallback() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .paused(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.lookingAway)
        coordinator.stopMonitoring()
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.pause])
        XCTAssertEqual(adapter.snapshotReadCount, 3)
        XCTAssertEqual(completedActions, [.pausedByGlanceHold])
        XCTAssertNil(coordinator.state.stoppedReason)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testPushedSnapshotPreservesManualTakeoverStopReason() async {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.75),
                .playing(speed: 1.0),
                PlayerSnapshot(playbackState: .playing, speed: 1.25, manualAction: .speedChanged)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)
        coordinator.applyPushedPlayerSnapshot(.playing(speed: 1.25))

        XCTAssertEqual(coordinator.state.stoppedReason, .manualPlayerTakeover)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testCommandFailureSuppressesFurtherCommandsUntilValidSnapshot() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playerUnavailable])
        adapter.failingCommands = [.holdSpeedAtOne]
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertFalse(coordinator.state.isPlayerControllable)
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

private func assertNoRestoreOrResume(_ commands: [PlaybackIntent]) {
    XCTAssertFalse(commands.contains(.resume))
    XCTAssertFalse(commands.contains { command in
        if case .restoreSpeed = command {
            return true
        }
        return false
    })
}

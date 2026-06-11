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

    func testPluginUpdateRequiredSnapshotsSendNoCommandAndAreNotControllable() async {
        let speedAdapter = FakeIINAPlaybackAdapter(snapshots: [.pluginUpdateRequired])
        let speedCoordinator = PlaybackCoordinator(mode: .speedControl, adapter: speedAdapter)

        await speedCoordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(speedAdapter.commands, [])
        XCTAssertFalse(speedCoordinator.state.isPlayerControllable)
        XCTAssertEqual(speedCoordinator.state.playerSnapshot, .pluginUpdateRequired)

        let pauseAdapter = FakeIINAPlaybackAdapter(snapshots: [.pluginUpdateRequired])
        let pauseCoordinator = PlaybackCoordinator(mode: .pauseResume, adapter: pauseAdapter)

        await pauseCoordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(pauseAdapter.commands, [])
        XCTAssertFalse(pauseCoordinator.state.isPlayerControllable)
        XCTAssertEqual(pauseCoordinator.state.playerSnapshot, .pluginUpdateRequired)
    }

    func testPluginUpdateRequiredDoesNotRestoreOrResumeOwnedPlayback() async {
        let speedAdapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.75),
                .playing(speed: 1.0),
                .pluginUpdateRequired
            ]
        )
        let speedCoordinator = PlaybackCoordinator(mode: .speedControl, adapter: speedAdapter)

        await speedCoordinator.handleAttentionState(.lookingAway)
        await speedCoordinator.handleAttentionState(.facing)

        XCTAssertEqual(speedAdapter.commands, [.holdSpeedAtOne])
        XCTAssertFalse(speedCoordinator.state.isPlayerControllable)
        XCTAssertEqual(speedCoordinator.state.playerSnapshot, .pluginUpdateRequired)
        assertNoRestoreOrResume(speedAdapter.commands)

        let pauseAdapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .paused(speed: 1.5),
                .pluginUpdateRequired
            ]
        )
        let pauseCoordinator = PlaybackCoordinator(mode: .pauseResume, adapter: pauseAdapter)

        await pauseCoordinator.handleAttentionState(.lookingAway)
        await pauseCoordinator.handleAttentionState(.facing)

        XCTAssertEqual(pauseAdapter.commands, [.pause])
        XCTAssertFalse(pauseCoordinator.state.isPlayerControllable)
        XCTAssertEqual(pauseCoordinator.state.playerSnapshot, .pluginUpdateRequired)
        assertNoRestoreOrResume(pauseAdapter.commands)
    }

    func testPluginUpdateRequiredCoordinatorStateMapsToPluginUpdateStatus() {
        let coordinatorState = PlaybackCoordinatorState(
            isPlayerControllable: false,
            playerSnapshot: .pluginUpdateRequired
        )

        let status = PlayerControlStatus(coordinatorState: coordinatorState)

        XCTAssertEqual(status, .pluginUpdateRequired)
        XCTAssertFalse(status.visibleTitle.isEmpty)
        XCTAssertFalse(status.detailText.isEmpty)
    }

    func testEachIntentIsFollowedByConfirmationSnapshot() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.snapshotReadCount, 2)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
    }

    func testDedupedStableFacingIsNotAPlayerFreshnessPath() async {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "99999999-9999-9999-9999-999999999999")!)
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .playing(speed: 1.5),
                .playing(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        for state in [DebouncedAttentionState.facing, .facing, .facing] {
            if deduper.shouldEmit(state) {
                await coordinator.handleAttentionState(state)
            }
        }

        XCTAssertEqual(adapter.snapshotReadCount, 1, "Stable repeated input is not a player freshness path.")
        XCTAssertEqual(adapter.commands, [], "Stable repeated input is not a player freshness path.")
    }

    func testDedupedAwayAndFacingTransitionsStillUseCommandConfirmationSnapshots() async {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
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

        for state in [DebouncedAttentionState.lookingAway, .lookingAway, .facing, .facing] {
            if deduper.shouldEmit(state) {
                await coordinator.handleAttentionState(state)
            }
        }

        XCTAssertEqual(adapter.snapshotReadCount, 4)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne, .restoreSpeed(1.25)])
        XCTAssertEqual(completedActions, [.heldSpeedAtOne, .restoredSpeed(1.25)])
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

    func testControllablePushedSnapshotReopensDedupedAwayStateAfterInitialNoOp() async {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!)
        var appPlayerStatus: PlayerControlStatus?
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .setupNeeded,
                .playing(speed: 1.5),
                .playing(speed: 1.0)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        coordinator.stateDidChange = { coordinatorState in
            let wasPlayerControllable = appPlayerStatus == .playing || appPlayerStatus == .paused
            appPlayerStatus = PlayerControlStatus(coordinatorState: coordinatorState)
            if coordinatorState.isPlayerControllable && !wasPlayerControllable {
                deduper.clearLastEmissionForActiveSession()
            }
        }

        XCTAssertTrue(deduper.shouldEmit(.lookingAway))
        await coordinator.handleAttentionState(.lookingAway)
        XCTAssertEqual(adapter.commands, [])
        XCTAssertFalse(deduper.shouldEmit(.lookingAway))

        coordinator.applyPushedPlayerSnapshot(.playing(speed: 1.5))

        XCTAssertTrue(deduper.shouldEmit(.lookingAway))
        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(adapter.snapshotReadCount, 3)
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

    func testPrePausedPlayerAtMonitoringStartKeepsMonitoringArmedWithoutOwningPause() async {
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.paused(speed: 1.5), .paused(speed: 1.5)])
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var requestedStops: [StopMonitoringReason] = []
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.stopMonitoringRequested = { requestedStops.append($0) }
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.facing)
        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(requestedStops, [])
        XCTAssertEqual(adapter.commands, [])
        XCTAssertEqual(completedActions, [])
        XCTAssertTrue(coordinator.state.isPlayerControllable)
        XCTAssertEqual(coordinator.state.playerSnapshot, .paused(speed: 1.5))
        XCTAssertNil(coordinator.state.stoppedReason)
        assertNoRestoreOrResume(adapter.commands)
    }

    func testPrePausedPlayerCanLaterBecomeControlledAfterPlaybackStarts() async {
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .paused(speed: 1.5),
                .playing(speed: 1.5),
                .playing(speed: 1.5),
                .paused(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .pauseResume, adapter: adapter)
        var requestedStops: [StopMonitoringReason] = []
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.stopMonitoringRequested = { requestedStops.append($0) }
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        await coordinator.handleAttentionState(.facing)
        await coordinator.handleAttentionState(.facing)
        await coordinator.handleAttentionState(.lookingAway)

        XCTAssertEqual(requestedStops, [])
        XCTAssertEqual(adapter.commands, [.pause])
        XCTAssertEqual(completedActions, [.pausedByGlanceHold])
        XCTAssertTrue(coordinator.state.isPlayerControllable)
        XCTAssertEqual(coordinator.state.playerSnapshot, .paused(speed: 1.5))
        XCTAssertNil(coordinator.state.stoppedReason)
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

    func testStopMonitoringInvalidatesInFlightAttentionBeforeCommandExecution() async {
        let adapter = SuspendingSnapshotPlaybackAdapter(snapshot: .playing(speed: 1.5))
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }

        let task = Task {
            await coordinator.handleAttentionState(.lookingAway)
        }
        await adapter.waitForSnapshotRequest()

        coordinator.stopMonitoring()
        adapter.resumeSnapshot()
        await task.value

        XCTAssertEqual(adapter.commands, [])
        XCTAssertEqual(completedActions, [])
        XCTAssertEqual(adapter.snapshotReadCount, 1)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
    }

    func testStopMonitoringInvalidatesInFlightAttentionDuringExecute() async {
        let adapter = SuspendingExecutePlaybackAdapter(
            snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        var stateChanges: [PlaybackCoordinatorState] = []
        var stopRequests: [StopMonitoringReason] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }
        coordinator.stateDidChange = { stateChanges.append($0) }
        coordinator.stopMonitoringRequested = { stopRequests.append($0) }

        let task = Task {
            await coordinator.handleAttentionState(.lookingAway)
        }
        await adapter.waitForExecuteRequest()

        coordinator.stopMonitoring()
        let commandsAfterStop = adapter.commands
        let stateChangesAfterStop = stateChanges

        adapter.resumeExecute()
        await task.value

        XCTAssertEqual(adapter.commands, commandsAfterStop)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(completedActions, [])
        XCTAssertEqual(stateChanges, stateChangesAfterStop)
        XCTAssertEqual(stopRequests, [])
        XCTAssertEqual(adapter.snapshotReadCount, 1)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        XCTAssertNil(coordinator.state.stoppedReason)
    }

    func testStopMonitoringInvalidatesInFlightAttentionDuringConfirmation() async {
        let adapter = SuspendingConfirmationSnapshotPlaybackAdapter(
            initialSnapshot: .playing(speed: 1.5),
            confirmationSnapshot: .playing(speed: 1.0)
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)
        var completedActions: [PlaybackCompletedAction] = []
        var stateChanges: [PlaybackCoordinatorState] = []
        var stopRequests: [StopMonitoringReason] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }
        coordinator.stateDidChange = { stateChanges.append($0) }
        coordinator.stopMonitoringRequested = { stopRequests.append($0) }

        let task = Task {
            await coordinator.handleAttentionState(.lookingAway)
        }
        await adapter.waitForConfirmationSnapshotRequest()

        coordinator.stopMonitoring()
        let commandsAfterStop = adapter.commands
        let stateChangesAfterStop = stateChanges

        adapter.resumeConfirmationSnapshot()
        await task.value

        XCTAssertEqual(adapter.commands, commandsAfterStop)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(completedActions, [])
        XCTAssertEqual(stateChanges, stateChangesAfterStop)
        XCTAssertEqual(stopRequests, [])
        XCTAssertEqual(adapter.snapshotReadCount, 2)
        XCTAssertFalse(coordinator.state.isPlayerControllable)
        XCTAssertNil(coordinator.state.stoppedReason)
    }

    func testInvalidatedAttentionDoesNotEmitCallbacksStopRequestsOrMisleadingDiagnostics() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let adapter = SuspendingConfirmationSnapshotPlaybackAdapter(
            initialSnapshot: .playing(speed: 1.5),
            confirmationSnapshot: .playing(speed: 1.0)
        )
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )
        var completedActions: [PlaybackCompletedAction] = []
        var stateChanges: [PlaybackCoordinatorState] = []
        var stopRequests: [StopMonitoringReason] = []
        coordinator.playbackActionDidComplete = { completedActions.append($0) }
        coordinator.stateDidChange = { stateChanges.append($0) }
        coordinator.stopMonitoringRequested = { stopRequests.append($0) }

        let task = Task {
            await coordinator.handleAttentionState(.lookingAway)
        }
        await adapter.waitForConfirmationSnapshotRequest()

        coordinator.stopMonitoring()
        let commandsAfterStop = adapter.commands
        let stateChangesAfterStop = stateChanges
        let diagnosticsAfterStop = recorder.events

        adapter.resumeConfirmationSnapshot()
        await task.value

        XCTAssertEqual(adapter.commands, commandsAfterStop)
        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne])
        XCTAssertEqual(completedActions, [])
        XCTAssertEqual(stateChanges, stateChangesAfterStop)
        XCTAssertEqual(stopRequests, [])
        XCTAssertEqual(recorder.events, diagnosticsAfterStop)
        XCTAssertFalse(recorder.events.contains { event in
            event.name == .playbackAction &&
                fieldValue(.confirmationOutcome, in: event) == "confirmed"
        })
        XCTAssertFalse(recorder.events.contains { event in
            event.name == .playbackAction &&
                fieldValue(.completedActionEmitted, in: event) != "none"
        })
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

    func testDefaultModePlaybackDiagnosticsStayQuietButFinalSummaryCountsActivity() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            kind: .monitoring
        )
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .default,
            diagnosticSession: session
        )

        await coordinator.handleAttentionState(.lookingAway)
        coordinator.stopMonitoring()

        XCTAssertFalse(recorder.events.contains { $0.name == .playbackAction })
        guard let summary = recorder.events.first(where: { $0.name == .runtimeSummary }) else {
            return XCTFail("Expected final playback runtime summary")
        }
        XCTAssertEqual(fieldValue(.summaryKind, in: summary), "final")
        XCTAssertEqual(fieldValue(.summarySource, in: summary), "playback")
        XCTAssertEqual(fieldValue(.playbackSnapshots, in: summary), "2")
        XCTAssertEqual(fieldValue(.playbackCommands, in: summary), "1")
    }

    func testCanceledAttentionTaskCompletesCommandConfirmationBeforeLaterRestore() async {
        let adapter = SelfCancelingCommandPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .playing(speed: 1.0),
                .playing(speed: 1.0),
                .playing(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(mode: .speedControl, adapter: adapter)

        let awayTask = Task {
            await coordinator.handleAttentionState(.lookingAway)
        }
        await awayTask.value

        await coordinator.handleAttentionState(.facing)

        XCTAssertEqual(adapter.commands, [.holdSpeedAtOne, .restoreSpeed(1.5)])
        XCTAssertEqual(adapter.snapshotReadCount, 4)
    }

    func testDiagnosticModeRecordsSpeedControlActionChainBreadcrumbs() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(kind: .monitoring)
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.25),
                .playing(speed: 1.0),
                .playing(speed: 1.0),
                .playing(speed: 1.25)
            ]
        )
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: session
        )

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        let actions = recorder.events.filter { $0.name == .playbackAction }
        XCTAssertEqual(actions.count, 2)
        assertPlaybackAction(
            actions[0],
            snapshotState: "playing",
            speedPresent: "true",
            intentType: "holdSpeedAtOne",
            commandType: "holdSpeedAtOne",
            confirmationOutcome: "confirmed",
            completedActionEmitted: "heldSpeedAtOne",
            errorCategory: "none"
        )
        assertPlaybackAction(
            actions[1],
            snapshotState: "playing",
            speedPresent: "true",
            intentType: "restoreSpeed",
            commandType: "restoreSpeed",
            confirmationOutcome: "confirmed",
            completedActionEmitted: "restoredSpeed",
            errorCategory: "none"
        )
    }

    func testDiagnosticModeRecordsPauseResumeActionChainBreadcrumbs() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                .playing(speed: 1.5),
                .paused(speed: 1.5),
                .paused(speed: 1.5),
                .playing(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(
            mode: .pauseResume,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)

        let actions = recorder.events.filter { $0.name == .playbackAction }
        XCTAssertEqual(actions.count, 2)
        assertPlaybackAction(
            actions[0],
            snapshotState: "playing",
            speedPresent: "true",
            intentType: "pause",
            commandType: "pause",
            confirmationOutcome: "confirmed",
            completedActionEmitted: "pausedByGlanceHold",
            errorCategory: "none"
        )
        assertPlaybackAction(
            actions[1],
            snapshotState: "paused",
            speedPresent: "true",
            intentType: "resume",
            commandType: "resume",
            confirmationOutcome: "confirmed",
            completedActionEmitted: "resumedPlayback",
            errorCategory: "none"
        )
    }

    func testDiagnosticModeRecordsCommandAndConfirmationFailuresWithoutCompletedAction() async throws {
        let commandRecorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let commandAdapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5)])
        commandAdapter.failingCommands = [.holdSpeedAtOne]
        let commandCoordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: commandAdapter,
            diagnosticRecorder: commandRecorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )
        var commandCompletedActions: [PlaybackCompletedAction] = []
        commandCoordinator.playbackActionDidComplete = { commandCompletedActions.append($0) }

        await commandCoordinator.handleAttentionState(.lookingAway)

        let commandFailure = try XCTUnwrap(commandRecorder.events.first { $0.name == .playbackAction })
        XCTAssertEqual(fieldValue(.confirmationOutcome, in: commandFailure), "notAttempted")
        XCTAssertEqual(fieldValue(.completedActionEmitted, in: commandFailure), "none")
        XCTAssertEqual(fieldValue(.errorCategory, in: commandFailure), "commandFailed")
        XCTAssertEqual(commandCompletedActions, [])

        let confirmationRecorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let confirmationAdapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.5)])
        let confirmationCoordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: confirmationAdapter,
            diagnosticRecorder: confirmationRecorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )
        var confirmationCompletedActions: [PlaybackCompletedAction] = []
        confirmationCoordinator.playbackActionDidComplete = { confirmationCompletedActions.append($0) }

        await confirmationCoordinator.handleAttentionState(.lookingAway)

        let confirmationFailure = try XCTUnwrap(confirmationRecorder.events.first { $0.name == .playbackAction })
        XCTAssertEqual(fieldValue(.confirmationOutcome, in: confirmationFailure), "failed")
        XCTAssertEqual(fieldValue(.completedActionEmitted, in: confirmationFailure), "none")
        XCTAssertEqual(fieldValue(.errorCategory, in: confirmationFailure), "confirmationFailed")
        XCTAssertEqual(confirmationCompletedActions, [])
    }

    func testPlaybackDiagnosticsShareMonitoringSessionAndIncreasingSequences() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            kind: .monitoring
        )
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.0)])
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: session
        )

        await coordinator.handleAttentionState(.lookingAway)
        coordinator.stopMonitoring()

        XCTAssertFalse(recorder.events.isEmpty)
        XCTAssertEqual(Set(recorder.events.map(\.sessionID)), [session.id])
        XCTAssertEqual(Set(recorder.events.map(\.sessionKind)), [.monitoring])
        XCTAssertEqual(recorder.events.map(\.sequence), recorder.events.map(\.sequence).sorted())
        XCTAssertTrue(recorder.events.contains { $0.category == .playback && $0.name == .playbackAction })
        XCTAssertTrue(recorder.events.contains { $0.category == .runtimeSummary && $0.name == .runtimeSummary })
    }

    func testDiagnosticModeCoalescesNoOpReasonSummaries() async throws {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(kind: .monitoring)
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                PlayerSnapshot(playbackState: .playing, speed: nil),
                PlayerSnapshot(playbackState: .playing, speed: nil),
                PlayerSnapshot(playbackState: .paused, speed: nil)
            ]
        )
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: session
        )

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)
        coordinator.stopMonitoring()

        let summaries = recorder.events.filter { $0.name == .playbackNoOpSummary }
        XCTAssertEqual(summaries.count, 1)
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(fieldValue(.noOpReason, in: summary), "missingSpeed")
        XCTAssertEqual(fieldValue(.noOpCount, in: summary), "3")
        XCTAssertEqual(fieldValue(.firstAttentionState, in: summary), "lookingAway")
        XCTAssertEqual(fieldValue(.latestAttentionState, in: summary), "facing")
        XCTAssertEqual(fieldValue(.firstSnapshotState, in: summary), "playing")
        XCTAssertEqual(fieldValue(.latestSnapshotState, in: summary), "paused")
        XCTAssertEqual(fieldValue(.firstSpeedPresent, in: summary), "false")
        XCTAssertEqual(fieldValue(.latestSpeedPresent, in: summary), "false")
        XCTAssertEqual(fieldValue(.firstIntentType, in: summary), "none")
        XCTAssertEqual(fieldValue(.latestIntentType, in: summary), "none")
        XCTAssertEqual(adapter.commands, [])
    }

    func testDiagnosticModeRecordsRepresentativeNoOpReasonsAtCoordinatorBoundary() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: FakeIINAPlaybackAdapter(
                snapshots: [
                    PlayerSnapshot(playbackState: .playing, speed: nil),
                    .idle,
                    .playing(speed: 1.5),
                    .playing(speed: 1.5)
                ]
            ),
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.recovering)
        await coordinator.handleAttentionState(.facing)
        coordinator.stopMonitoring()

        let reasons = recorder.events
            .filter { $0.name == .playbackNoOpSummary }
            .compactMap { fieldValue(.noOpReason, in: $0) }

        XCTAssertEqual(Set(reasons), [
            "missingSpeed",
            "playerNotControllable",
            "recoveringNoCommand",
            "policyEvaluatedWithoutIntent"
        ])
    }

    func testPluginUpdateRequiredDiagnosticNameIsScalarAndPrivacySafe() async throws {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: FakeIINAPlaybackAdapter(snapshots: [.pluginUpdateRequired]),
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )

        await coordinator.handleAttentionState(.lookingAway)
        coordinator.stopMonitoring()

        let summary = try XCTUnwrap(recorder.events.first { $0.name == .playbackNoOpSummary })
        XCTAssertEqual(fieldValue(.noOpReason, in: summary), "playerNotControllable")
        XCTAssertEqual(fieldValue(.firstSnapshotState, in: summary), "pluginUpdateRequired")
        XCTAssertEqual(fieldValue(.latestSnapshotState, in: summary), "pluginUpdateRequired")
        XCTAssertEqual(fieldValue(.firstIntentType, in: summary), "none")
        XCTAssertEqual(fieldValue(.latestIntentType, in: summary), "none")

        let forbiddenFragments = [
            "unauthorized",
            "payload",
            "token",
            "media",
            "title",
            "path",
            "frame",
            "camera",
            "vision"
        ]
        let loggedValues = summary.fields.map { $0.value.logValue.lowercased() }

        for fragment in forbiddenFragments {
            XCTAssertFalse(
                loggedValues.contains { $0.contains(fragment) },
                "Diagnostic values must not contain private/raw fragment: \(fragment)"
            )
        }
    }

    func testDefaultModeRecordsNoNoOpReasonDetailsIncludingFinalSummaries() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(kind: .monitoring)
        let adapter = FakeIINAPlaybackAdapter(
            snapshots: [
                PlayerSnapshot(playbackState: .playing, speed: nil),
                .idle,
                .playing(speed: 1.5)
            ]
        )
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .default,
            diagnosticSession: session
        )

        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.lookingAway)
        await coordinator.handleAttentionState(.facing)
        coordinator.stopMonitoring()

        XCTAssertFalse(recorder.events.contains { $0.name == .playbackNoOpSummary })
        for event in recorder.events {
            XCTAssertFalse(event.fields.contains { field in
                [
                    DiagnosticFieldName.noOpReason,
                    .noOpCount,
                    .firstAttentionState,
                    .latestAttentionState,
                    .firstSnapshotState,
                    .latestSnapshotState,
                    .firstSpeedPresent,
                    .latestSpeedPresent,
                    .firstIntentType,
                    .latestIntentType
                ].contains(field.name)
            })
        }
    }

    func testRepeatedStableSuppressionRecordsBoundedNoOpEvidenceWithoutPlaybackWork() async throws {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let session = DiagnosticSession(kind: .monitoring)
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: session
        )
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(session.id)

        for state in [DebouncedAttentionState.facing, .facing, .facing] {
            if deduper.shouldEmit(state) {
                await coordinator.handleAttentionState(state)
            } else if deduper.suppressionReason(for: state) == .repeatedStableStateNoCommand {
                coordinator.recordSuppressedRepeatedStableStateNoCommand(state)
            }
        }
        coordinator.stopMonitoring()

        XCTAssertEqual(adapter.snapshotReadCount, 1)
        XCTAssertEqual(adapter.commands, [])

        let repeatedSummary = try XCTUnwrap(
            recorder.events.first {
                $0.name == .playbackNoOpSummary &&
                    fieldValue(.noOpReason, in: $0) == "repeatedStableStateNoCommand"
            }
        )
        XCTAssertEqual(fieldValue(.noOpCount, in: repeatedSummary), "2")
        XCTAssertEqual(fieldValue(.firstAttentionState, in: repeatedSummary), "facing")
        XCTAssertEqual(fieldValue(.latestAttentionState, in: repeatedSummary), "facing")
        XCTAssertEqual(fieldValue(.firstSnapshotState, in: repeatedSummary), "notRead")
        XCTAssertEqual(fieldValue(.latestSnapshotState, in: repeatedSummary), "notRead")
        XCTAssertEqual(fieldValue(.firstIntentType, in: repeatedSummary), "none")
        XCTAssertEqual(fieldValue(.latestIntentType, in: repeatedSummary), "none")
    }

    func testRepeatedStableSuppressionStaysQuietInDefaultMode() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .default)
        let session = DiagnosticSession(kind: .monitoring)
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .default,
            diagnosticSession: session
        )

        coordinator.recordSuppressedRepeatedStableStateNoCommand(.facing)
        coordinator.recordSuppressedRepeatedStableStateNoCommand(.facing)
        coordinator.stopMonitoring()

        XCTAssertEqual(adapter.snapshotReadCount, 0)
        XCTAssertEqual(adapter.commands, [])
        XCTAssertFalse(recorder.events.contains { $0.name == .playbackNoOpSummary })
    }

    func testNoIntentPlaybackEvaluationsEmitBoundedNoOpSummaryInDiagnosticMode() async {
        let recorder = PlaybackDiagnosticRecorder(mode: .diagnostic)
        let adapter = FakeIINAPlaybackAdapter(snapshots: [.playing(speed: 1.5), .playing(speed: 1.5)])
        let coordinator = PlaybackCoordinator(
            mode: .speedControl,
            adapter: adapter,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            diagnosticSession: DiagnosticSession(kind: .monitoring)
        )

        await coordinator.handleAttentionState(.facing)
        await coordinator.handleAttentionState(.facing)
        coordinator.stopMonitoring()

        XCTAssertFalse(recorder.events.contains { $0.name == .playbackAction })
        XCTAssertTrue(recorder.events.contains { $0.name == .runtimeSummary })
        XCTAssertEqual(recorder.events.filter { $0.name == .playbackNoOpSummary }.count, 1)
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

private final class PlaybackDiagnosticRecorder: DiagnosticRecording {
    let mode: DiagnosticMode
    private(set) var events: [DiagnosticEvent] = []

    init(mode: DiagnosticMode) {
        self.mode = mode
    }

    @discardableResult
    func record(_ request: DiagnosticEventRequest, in session: DiagnosticSession) -> DiagnosticEvent? {
        guard DiagnosticEventPolicy.shouldRecord(request, mode: mode) else {
            return nil
        }

        let event = DiagnosticEvent(
            category: request.category,
            name: request.name,
            sessionID: session.id,
            sessionKind: session.kind,
            sequence: session.nextSequence(),
            fields: request.fields
        )
        events.append(event)
        return event
    }
}

private final class SelfCancelingCommandPlaybackAdapter: IINAPlaybackAdapting {
    private var snapshots: [PlayerSnapshot]
    private(set) var commands: [PlaybackIntent] = []
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
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

private final class SuspendingSnapshotPlaybackAdapter: IINAPlaybackAdapting {
    private let snapshotResult: PlayerSnapshot
    private var snapshotContinuation: CheckedContinuation<PlayerSnapshot, Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private(set) var commands: [PlaybackIntent] = []
    private(set) var snapshotReadCount = 0

    init(snapshot: PlayerSnapshot) {
        self.snapshotResult = snapshot
    }

    func snapshot() async -> PlayerSnapshot {
        snapshotReadCount += 1
        requestContinuation?.resume()
        requestContinuation = nil

        return await withCheckedContinuation { continuation in
            snapshotContinuation = continuation
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        commands.append(intent)
    }

    func waitForSnapshotRequest() async {
        guard snapshotReadCount == 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func resumeSnapshot() {
        snapshotContinuation?.resume(returning: snapshotResult)
        snapshotContinuation = nil
    }
}

private final class SuspendingExecutePlaybackAdapter: IINAPlaybackAdapting {
    private var snapshots: [PlayerSnapshot]
    private var executeContinuation: CheckedContinuation<Void, Never>?
    private var executeRequestContinuation: CheckedContinuation<Void, Never>?
    private var shouldResumeExecuteImmediately = false
    private(set) var commands: [PlaybackIntent] = []
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
        executeRequestContinuation?.resume()
        executeRequestContinuation = nil

        await withCheckedContinuation { continuation in
            if shouldResumeExecuteImmediately {
                shouldResumeExecuteImmediately = false
                continuation.resume()
            } else {
                executeContinuation = continuation
            }
        }
    }

    func waitForExecuteRequest() async {
        guard commands.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            executeRequestContinuation = continuation
        }
    }

    func resumeExecute() {
        if let executeContinuation {
            executeContinuation.resume()
            self.executeContinuation = nil
        } else {
            shouldResumeExecuteImmediately = true
        }
    }
}

private final class SuspendingConfirmationSnapshotPlaybackAdapter: IINAPlaybackAdapting {
    private let initialSnapshot: PlayerSnapshot
    private let confirmationSnapshot: PlayerSnapshot
    private var confirmationSnapshotContinuation: CheckedContinuation<PlayerSnapshot, Never>?
    private var confirmationRequestContinuation: CheckedContinuation<Void, Never>?
    private var shouldResumeConfirmationImmediately = false
    private(set) var commands: [PlaybackIntent] = []
    private(set) var snapshotReadCount = 0

    init(initialSnapshot: PlayerSnapshot, confirmationSnapshot: PlayerSnapshot) {
        self.initialSnapshot = initialSnapshot
        self.confirmationSnapshot = confirmationSnapshot
    }

    func snapshot() async -> PlayerSnapshot {
        snapshotReadCount += 1

        guard snapshotReadCount > 1 else {
            return initialSnapshot
        }

        confirmationRequestContinuation?.resume()
        confirmationRequestContinuation = nil

        return await withCheckedContinuation { continuation in
            if shouldResumeConfirmationImmediately {
                shouldResumeConfirmationImmediately = false
                continuation.resume(returning: confirmationSnapshot)
            } else {
                confirmationSnapshotContinuation = continuation
            }
        }
    }

    func execute(_ intent: PlaybackIntent) async throws {
        commands.append(intent)
    }

    func waitForConfirmationSnapshotRequest() async {
        guard snapshotReadCount < 2 else {
            return
        }

        await withCheckedContinuation { continuation in
            confirmationRequestContinuation = continuation
        }
    }

    func resumeConfirmationSnapshot() {
        if let confirmationSnapshotContinuation {
            confirmationSnapshotContinuation.resume(returning: confirmationSnapshot)
            self.confirmationSnapshotContinuation = nil
        } else {
            shouldResumeConfirmationImmediately = true
        }
    }
}

private func assertPlaybackAction(
    _ event: DiagnosticEvent,
    snapshotState: String,
    speedPresent: String,
    intentType: String,
    commandType: String,
    confirmationOutcome: String,
    completedActionEmitted: String,
    errorCategory: String
) {
    XCTAssertEqual(event.category, .playback)
    XCTAssertEqual(fieldValue(.snapshotState, in: event), snapshotState)
    XCTAssertEqual(fieldValue(.speedPresent, in: event), speedPresent)
    XCTAssertEqual(fieldValue(.intentType, in: event), intentType)
    XCTAssertEqual(fieldValue(.commandType, in: event), commandType)
    XCTAssertEqual(fieldValue(.confirmationOutcome, in: event), confirmationOutcome)
    XCTAssertEqual(fieldValue(.completedActionEmitted, in: event), completedActionEmitted)
    XCTAssertEqual(fieldValue(.errorCategory, in: event), errorCategory)
}

private func fieldValue(_ name: DiagnosticFieldName, in event: DiagnosticEvent) -> String? {
    event.fields.first { $0.name == name }?.value.logValue
}

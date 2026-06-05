import XCTest
@testable import GlanceHold

final class PlaybackPolicyTests: XCTestCase {
    func testSpeedModeAwayCapturesOriginalSpeedAndHoldsAtOneOnce() {
        var policy = PlaybackPolicy(mode: .speedControl)

        let first = policy.apply(attention: .lookingAway, player: .playing(speed: 1.75))
        XCTAssertEqual(first.intents, [.holdSpeedAtOne])
        XCTAssertEqual(first.state.capturedSpeed, 1.75)

        let repeatedAway = policy.apply(attention: .lookingAway, player: .playing(speed: 1.0))
        XCTAssertEqual(repeatedAway.intents, [])
        XCTAssertEqual(repeatedAway.state.capturedSpeed, 1.75)

        let repeatedNoFace = policy.apply(attention: .noFaceDetected, player: .playing(speed: 1.0))
        XCTAssertEqual(repeatedNoFace.intents, [])
        XCTAssertEqual(repeatedNoFace.state.capturedSpeed, 1.75)
    }

    func testSpeedModeFacingRestoresCapturedSpeedWhileOwned() {
        var policy = PlaybackPolicy(mode: .speedControl)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 1.75)).intents, [.holdSpeedAtOne])

        let result = policy.apply(attention: .facing, player: .playing(speed: 1.0))

        XCTAssertEqual(result.intents, [.restoreSpeed(1.75)])
        XCTAssertNil(result.state.capturedSpeed)
    }

    func testSpeedModeRestoresArbitraryCapturedSpeeds() {
        for speed in [1.25, 1.5, 2.0] {
            var policy = PlaybackPolicy(mode: .speedControl)

            XCTAssertEqual(policy.apply(attention: .noFaceDetected, player: .playing(speed: speed)).intents, [.holdSpeedAtOne])
            XCTAssertEqual(policy.apply(attention: .facing, player: .playing(speed: 1.0)).intents, [.restoreSpeed(speed)])
        }
    }

    func testObservedSpeedChangeWhileOwnedStopsMonitoringWithoutRestore() {
        var policy = PlaybackPolicy(mode: .speedControl)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 1.75)).intents, [.holdSpeedAtOne])

        let result = policy.apply(attention: .lookingAway, player: .playing(speed: 1.25))

        XCTAssertEqual(result.intents, [.stopMonitoring(reason: .manualPlayerTakeover)])
        XCTAssertNil(result.state.capturedSpeed)
        XCTAssertFalse(result.state.pauseOwnedByGlanceHold)
        XCTAssertEqual(result.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(result.intents)
    }

    func testManualSpeedChangedActionWhileOwnedStopsMonitoringWithoutRestore() {
        var policy = PlaybackPolicy(mode: .speedControl)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 1.75)).intents, [.holdSpeedAtOne])

        let result = policy.apply(
            attention: .lookingAway,
            player: PlayerSnapshot(playbackState: .playing, speed: 1.0, manualAction: .speedChanged)
        )

        XCTAssertEqual(result.intents, [.stopMonitoring(reason: .manualPlayerTakeover)])
        XCTAssertNil(result.state.capturedSpeed)
        XCTAssertFalse(result.state.pauseOwnedByGlanceHold)
        XCTAssertEqual(result.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(result.intents)
    }

    func testPauseModeAwayPausesOnceAndFacingResumesOnlyOwnedPause() {
        var policy = PlaybackPolicy(mode: .pauseResume)

        let pause = policy.apply(attention: .lookingAway, player: .playing(speed: 1.5))
        XCTAssertEqual(pause.intents, [.pause])
        XCTAssertTrue(pause.state.pauseOwnedByGlanceHold)

        let repeated = policy.apply(attention: .noFaceDetected, player: .paused(speed: 1.5))
        XCTAssertEqual(repeated.intents, [])
        XCTAssertTrue(repeated.state.pauseOwnedByGlanceHold)

        let resume = policy.apply(attention: .facing, player: .paused(speed: 1.5))
        XCTAssertEqual(resume.intents, [.resume])
        XCTAssertFalse(resume.state.pauseOwnedByGlanceHold)
    }

    func testAlreadyPausedBeforeAwayIsNotResumed() {
        var policy = PlaybackPolicy(mode: .pauseResume)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .paused(speed: 1.5)).intents, [])
        XCTAssertFalse(policy.apply(attention: .facing, player: .paused(speed: 1.5)).intents.contains(.resume))
    }

    func testManualPlayPressedWhilePauseOwnedStopsMonitoringWithoutResume() {
        var policy = PlaybackPolicy(mode: .pauseResume)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 1.5)).intents, [.pause])

        let result = policy.apply(
            attention: .facing,
            player: PlayerSnapshot(playbackState: .paused, speed: 1.5, manualAction: .playPressed)
        )

        XCTAssertEqual(result.intents, [.stopMonitoring(reason: .manualPlayerTakeover)])
        XCTAssertNil(result.state.capturedSpeed)
        XCTAssertFalse(result.state.pauseOwnedByGlanceHold)
        XCTAssertEqual(result.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(result.intents)
    }

    func testManualPausePressedWhilePauseOwnedStopsMonitoringWithoutResume() {
        var policy = PlaybackPolicy(mode: .pauseResume)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 1.5)).intents, [.pause])

        let result = policy.apply(
            attention: .lookingAway,
            player: PlayerSnapshot(playbackState: .paused, speed: 1.5, manualAction: .pausePressed)
        )

        XCTAssertEqual(result.intents, [.stopMonitoring(reason: .manualPlayerTakeover)])
        XCTAssertNil(result.state.capturedSpeed)
        XCTAssertFalse(result.state.pauseOwnedByGlanceHold)
        XCTAssertEqual(result.state.stoppedReason, .manualPlayerTakeover)
        assertNoRestoreOrResume(result.intents)
    }

    func testManualTakeoverRequiresExplicitReEnable() {
        var policy = PlaybackPolicy(mode: .speedControl, manualTakeoverPolicy: .stopMonitoring)

        XCTAssertEqual(policy.apply(attention: .lookingAway, player: .playing(speed: 2.0)).intents, [.holdSpeedAtOne])
        XCTAssertEqual(
            policy.apply(
                attention: .lookingAway,
                player: PlayerSnapshot(playbackState: .playing, speed: 1.0, manualAction: .speedChanged)
            ).intents,
            [.stopMonitoring(reason: .manualPlayerTakeover)]
        )

        let stoppedAway = policy.apply(attention: .lookingAway, player: .playing(speed: 2.0))
        XCTAssertEqual(stoppedAway.intents, [])
        XCTAssertEqual(stoppedAway.state.stoppedReason, .manualPlayerTakeover)

        let stoppedFacing = policy.apply(attention: .facing, player: .playing(speed: 2.0))
        XCTAssertEqual(stoppedFacing.intents, [])
        XCTAssertEqual(stoppedFacing.state.stoppedReason, .manualPlayerTakeover)
    }

    func testRecoveringUnavailableIdleAndPlayerUnavailableAreSafeNoops() {
        for attention in [DebouncedAttentionState.recovering, .unavailable] {
            var speedPolicy = PlaybackPolicy(mode: .speedControl)
            XCTAssertEqual(speedPolicy.apply(attention: attention, player: .playing(speed: 1.75)).intents, [])

            var pausePolicy = PlaybackPolicy(mode: .pauseResume)
            XCTAssertEqual(pausePolicy.apply(attention: attention, player: .playing(speed: 1.75)).intents, [])
        }

        var speedPolicy = PlaybackPolicy(mode: .speedControl)
        XCTAssertEqual(speedPolicy.apply(attention: .lookingAway, player: .idle).intents, [])
        XCTAssertEqual(speedPolicy.apply(attention: .lookingAway, player: .playerUnavailable).intents, [])

        var pausePolicy = PlaybackPolicy(mode: .pauseResume)
        XCTAssertEqual(pausePolicy.apply(attention: .lookingAway, player: .idle).intents, [])
        XCTAssertEqual(pausePolicy.apply(attention: .lookingAway, player: .playerUnavailable).intents, [])
    }

    func testMissingSpeedSnapshotsAreSafeNoops() {
        var speedPolicy = PlaybackPolicy(mode: .speedControl)
        XCTAssertEqual(
            speedPolicy.apply(
                attention: .lookingAway,
                player: PlayerSnapshot(playbackState: .playing, speed: nil)
            ).intents,
            []
        )

        var ownedSpeedPolicy = PlaybackPolicy(mode: .speedControl)
        XCTAssertEqual(ownedSpeedPolicy.apply(attention: .lookingAway, player: .playing(speed: 1.75)).intents, [.holdSpeedAtOne])
        let missingRestore = ownedSpeedPolicy.apply(
            attention: .facing,
            player: PlayerSnapshot(playbackState: .playing, speed: nil)
        )
        XCTAssertEqual(missingRestore.intents, [])
        XCTAssertEqual(missingRestore.state.capturedSpeed, 1.75)

        var pausePolicy = PlaybackPolicy(mode: .pauseResume)
        XCTAssertEqual(
            pausePolicy.apply(
                attention: .lookingAway,
                player: PlayerSnapshot(playbackState: .playing, speed: nil)
            ).intents,
            []
        )

        var ownedPausePolicy = PlaybackPolicy(mode: .pauseResume)
        XCTAssertEqual(ownedPausePolicy.apply(attention: .lookingAway, player: .playing(speed: 1.5)).intents, [.pause])
        let missingResume = ownedPausePolicy.apply(
            attention: .facing,
            player: PlayerSnapshot(playbackState: .paused, speed: nil)
        )
        XCTAssertEqual(missingResume.intents, [])
        XCTAssertTrue(missingResume.state.pauseOwnedByGlanceHold)
    }

    private func assertNoRestoreOrResume(_ intents: [PlaybackIntent]) {
        XCTAssertFalse(intents.contains(.resume))
        XCTAssertFalse(intents.contains { intent in
            if case .restoreSpeed = intent {
                return true
            }
            return false
        })
    }
}

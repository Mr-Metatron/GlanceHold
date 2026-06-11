import XCTest
@testable import GlanceHold

final class AttentionStateMachineTests: XCTestCase {
    func testStableFacingRemainsFacing() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.facing, at: 0.4)), .facing)
        XCTAssertEqual(machine.apply(sample(.facing, at: 1.2)), .facing)
    }

    func testBriefAwayUnderAwayDelayRemainsFacing() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 1.1)), .facing)
    }

    func testSustainedAwayAtAwayDelayBecomesLookingAway() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 1.2)), .lookingAway)
    }

    func testSustainedNoFaceAtAwayDelayBecomesNoFaceDetected() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.noFace, at: 0.4)), .facing)
        XCTAssertEqual(machine.apply(sample(.noFace, at: 1.4)), .noFaceDetected)
    }

    func testFacingAfterAbsentStateRecoversBeforeReturningFacing() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 1.2)), .lookingAway)
        XCTAssertEqual(machine.apply(sample(.facing, at: 1.3)), .recovering)
        XCTAssertEqual(machine.apply(sample(.facing, at: 1.89)), .recovering)
        XCTAssertEqual(machine.apply(sample(.facing, at: 1.9)), .facing)
    }

    func testJitterAndMixedSignalsBelowThresholdDoNotChurnState() {
        var machine = AttentionStateMachine()

        XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
        XCTAssertEqual(machine.apply(sample(.facing, at: 0.5)), .facing)
        XCTAssertEqual(machine.apply(sample(.noFace, at: 0.8)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 1.1)), .facing)
        XCTAssertEqual(machine.apply(sample(.facing, at: 1.4)), .facing)
    }

    func testUnsafeSignalsReturnUnavailableAndDoNotCreateRecovery() {
        for signal in explicitProblemSignals() {
            var machine = AttentionStateMachine()

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.2)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.facing, at: 0.8)), .facing)
        }
    }

    func testUnsafeSignalsResetPendingAwayCandidate() {
        for signal in explicitProblemSignals() {
            var machine = AttentionStateMachine()

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.8)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.away, at: 1.2)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.away, at: 2.2)), .lookingAway)
        }
    }

    func testUnknownDuringRecoveryPausesWithoutCountingAsFacingTime() {
        var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

        XCTAssertEqual(machine.apply(sample(.away, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.away, at: 1.0)), .lookingAway)

        let recoveryStarted = machine.applyWithDiagnostics(sample(.facing, at: 1.1))
        let paused = machine.applyWithDiagnostics(sample(.unknown, at: 1.3))
        let resumed = machine.applyWithDiagnostics(sample(.facing, at: 1.7))

        XCTAssertEqual(recoveryStarted.nextState, .recovering)
        XCTAssertEqual(recoveryStarted.candidateSignal, .facing)
        XCTAssertEqual(recoveryStarted.candidateStartedAt, 1.1)

        XCTAssertEqual(paused.previousState, .recovering)
        XCTAssertEqual(paused.nextState, .recovering)
        XCTAssertEqual(paused.candidateSignal, .facing)
        XCTAssertEqual(paused.candidateStartedAt, 1.1)
        XCTAssertEqual(paused.elapsedSinceCandidateStart ?? -1.0, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(paused.requiredThreshold, 0.6)

        XCTAssertEqual(resumed.previousState, .recovering)
        XCTAssertEqual(resumed.nextState, .recovering)
        XCTAssertEqual(resumed.candidateSignal, .facing)
        XCTAssertEqual(resumed.elapsedSinceCandidateStart ?? -1.0, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(resumed.requiredThreshold, 0.6)

        XCTAssertEqual(machine.apply(sample(.facing, at: 2.09)), .recovering)
        XCTAssertEqual(machine.apply(sample(.facing, at: 2.1)), .facing)
    }

    func testAmbiguousDuringNoFaceRecoveryPausesWithoutClearingCandidate() {
        var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

        XCTAssertEqual(machine.apply(sample(.noFace, at: 0.0)), .facing)
        XCTAssertEqual(machine.apply(sample(.noFace, at: 1.0)), .noFaceDetected)

        let started = machine.applyWithDiagnostics(sample(.facing, at: 1.1))
        let paused = machine.applyWithDiagnostics(sample(.ambiguous, at: 1.3))
        let resumed = machine.applyWithDiagnostics(sample(.facing, at: 1.7))

        XCTAssertEqual(started.nextState, .recovering)
        XCTAssertEqual(paused.previousState, .recovering)
        XCTAssertEqual(paused.nextState, .recovering)
        XCTAssertEqual(paused.candidateSignal, .facing)
        XCTAssertEqual(paused.candidateStartedAt, 1.1)
        XCTAssertEqual(paused.elapsedSinceCandidateStart ?? -1.0, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(paused.requiredThreshold, 0.6)

        XCTAssertEqual(resumed.nextState, .recovering)
        XCTAssertEqual(resumed.elapsedSinceCandidateStart ?? -1.0, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(machine.apply(sample(.facing, at: 2.1)), .facing)
    }

    func testShortUncertaintyKeepsStableStateAndSustainedUncertaintyBecomesUnavailable() {
        for signal in uncertaintySignals() {
            var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.1)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.69)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.7)), .unavailable)
        }
    }

    func testShortUncertaintyKeepsAwayAndNoFaceStableStates() {
        for signal in uncertaintySignals() {
            var awayMachine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

            XCTAssertEqual(awayMachine.apply(sample(.away, at: 0.0)), .facing)
            XCTAssertEqual(awayMachine.apply(sample(.away, at: 1.0)), .lookingAway)
            XCTAssertEqual(awayMachine.apply(sample(signal, at: 1.1)), .lookingAway)
            XCTAssertEqual(awayMachine.apply(sample(signal, at: 1.69)), .lookingAway)

            var noFaceMachine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

            XCTAssertEqual(noFaceMachine.apply(sample(.noFace, at: 0.0)), .facing)
            XCTAssertEqual(noFaceMachine.apply(sample(.noFace, at: 1.0)), .noFaceDetected)
            XCTAssertEqual(noFaceMachine.apply(sample(signal, at: 1.1)), .noFaceDetected)
            XCTAssertEqual(noFaceMachine.apply(sample(signal, at: 1.69)), .noFaceDetected)
        }
    }

    func testFacingAfterSustainedUnavailableRequiresRecoveryDelay() {
        for signal in uncertaintySignals() {
            var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.1)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.7)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.facing, at: 0.8)), .recovering)
            XCTAssertEqual(machine.apply(sample(.facing, at: 1.39)), .recovering)
            XCTAssertEqual(machine.apply(sample(.facing, at: 1.4)), .facing)
        }
    }

    func testExplicitProblemSignalsStillReturnUnavailableImmediately() {
        for signal in explicitProblemSignals() {
            var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

            XCTAssertEqual(machine.apply(sample(.away, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(.away, at: 1.0)), .lookingAway)
            XCTAssertEqual(machine.apply(sample(.facing, at: 1.1)), .recovering)
            XCTAssertEqual(machine.apply(sample(signal, at: 1.2)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.facing, at: 1.3)), .facing)
        }
    }

    func testAttentionTimingDefaultsAreUsedForThresholdEdges() {
        let timing = AttentionTiming()

        XCTAssertEqual(timing.awayDelay, 1.0)
        XCTAssertEqual(timing.recoveryDelay, 0.6)
    }

    func testDiagnosticResultReportsStableFacingWithoutChangingState() {
        var machine = AttentionStateMachine()

        let result = machine.applyWithDiagnostics(sample(.facing, at: 0.0))

        XCTAssertEqual(result.rawSignal, .facing)
        XCTAssertEqual(result.previousState, .facing)
        XCTAssertEqual(result.nextState, .facing)
        XCTAssertEqual(result.previousEmittedState, .facing)
        XCTAssertNil(result.candidateSignal)
        XCTAssertNil(result.candidateStartedAt)
        XCTAssertNil(result.elapsedSinceCandidateStart)
        XCTAssertNil(result.requiredThreshold)
        XCTAssertEqual(result.reason, .stable)
    }

    func testDiagnosticResultReportsAwayCandidateThresholdPendingAndReached() {
        var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

        _ = machine.applyWithDiagnostics(sample(.facing, at: 0.0))
        let started = machine.applyWithDiagnostics(sample(.away, at: 0.2))
        let pending = machine.applyWithDiagnostics(sample(.away, at: 1.1))
        let reached = machine.applyWithDiagnostics(sample(.away, at: 1.2))

        XCTAssertEqual(started.previousState, .facing)
        XCTAssertEqual(started.nextState, .facing)
        XCTAssertEqual(started.candidateSignal, .away)
        XCTAssertEqual(started.candidateStartedAt, 0.2)
        XCTAssertEqual(started.elapsedSinceCandidateStart, 0.0)
        XCTAssertEqual(started.requiredThreshold, 1.0)
        XCTAssertEqual(started.reason, .candidateStarted)

        XCTAssertEqual(pending.previousState, .facing)
        XCTAssertEqual(pending.nextState, .facing)
        XCTAssertEqual(pending.candidateSignal, .away)
        XCTAssertEqual(pending.candidateStartedAt, 0.2)
        XCTAssertEqual(pending.elapsedSinceCandidateStart ?? -1.0, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(pending.requiredThreshold, 1.0)
        XCTAssertEqual(pending.reason, .thresholdPending)

        XCTAssertEqual(reached.previousState, .facing)
        XCTAssertEqual(reached.nextState, .lookingAway)
        XCTAssertNil(reached.candidateSignal)
        XCTAssertNil(reached.candidateStartedAt)
        XCTAssertEqual(reached.elapsedSinceCandidateStart, 1.0)
        XCTAssertEqual(reached.requiredThreshold, 1.0)
        XCTAssertEqual(reached.reason, .thresholdReached)
    }

    func testDiagnosticResultReportsRecoveryCandidateAndThreshold() {
        var machine = AttentionStateMachine(timing: AttentionTiming(awayDelay: 1.0, recoveryDelay: 0.6))

        _ = machine.apply(sample(.away, at: 0.0))
        _ = machine.apply(sample(.away, at: 1.0))

        let started = machine.applyWithDiagnostics(sample(.facing, at: 1.1))
        let reached = machine.applyWithDiagnostics(sample(.facing, at: 1.7))

        XCTAssertEqual(started.previousState, .lookingAway)
        XCTAssertEqual(started.nextState, .recovering)
        XCTAssertEqual(started.candidateSignal, .facing)
        XCTAssertEqual(started.candidateStartedAt, 1.1)
        XCTAssertEqual(started.requiredThreshold, 0.6)
        XCTAssertEqual(started.reason, .candidateStarted)

        XCTAssertEqual(reached.previousState, .recovering)
        XCTAssertEqual(reached.nextState, .facing)
        XCTAssertNil(reached.candidateSignal)
        XCTAssertEqual(reached.elapsedSinceCandidateStart ?? -1.0, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(reached.requiredThreshold, 0.6)
        XCTAssertEqual(reached.reason, .thresholdReached)
    }

    func testDiagnosticResultReportsCandidateResetAndUnavailable() {
        var machine = AttentionStateMachine()

        _ = machine.applyWithDiagnostics(sample(.away, at: 0.2))
        let reset = machine.applyWithDiagnostics(sample(.noFace, at: 0.3))
        let unavailable = machine.applyWithDiagnostics(sample(.cameraUnavailable, at: 0.4))

        XCTAssertEqual(reset.rawSignal, .noFace)
        XCTAssertEqual(reset.previousState, .facing)
        XCTAssertEqual(reset.nextState, .facing)
        XCTAssertEqual(reset.candidateSignal, .noFace)
        XCTAssertEqual(reset.candidateStartedAt, 0.3)
        XCTAssertEqual(reset.requiredThreshold, 1.0)
        XCTAssertEqual(reset.reason, .candidateReset)

        XCTAssertEqual(unavailable.rawSignal, .cameraUnavailable)
        XCTAssertEqual(unavailable.previousState, .facing)
        XCTAssertEqual(unavailable.nextState, .unavailable)
        XCTAssertNil(unavailable.candidateSignal)
        XCTAssertNil(unavailable.candidateStartedAt)
        XCTAssertNil(unavailable.requiredThreshold)
        XCTAssertEqual(unavailable.reason, .unavailable)
    }

    private func sample(_ signal: RawAttentionSignal, at time: TimeInterval) -> RawAttentionSample {
        RawAttentionSample(signal: signal, time: time)
    }

    private func uncertaintySignals() -> [RawAttentionSignal] {
        [
            .ambiguous,
            .unknown
        ]
    }

    private func explicitProblemSignals() -> [RawAttentionSignal] {
        [
            .uncalibrated,
            .cameraPermissionDenied,
            .cameraUnavailable
        ]
    }
}

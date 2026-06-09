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
        for signal in unsafeSignals() {
            var machine = AttentionStateMachine()

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.2)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.facing, at: 0.8)), .facing)
        }
    }

    func testUnsafeSignalsResetPendingAwayCandidate() {
        for signal in unsafeSignals() {
            var machine = AttentionStateMachine()

            XCTAssertEqual(machine.apply(sample(.facing, at: 0.0)), .facing)
            XCTAssertEqual(machine.apply(sample(.away, at: 0.2)), .facing)
            XCTAssertEqual(machine.apply(sample(signal, at: 0.8)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.away, at: 1.2)), .unavailable)
            XCTAssertEqual(machine.apply(sample(.away, at: 2.2)), .lookingAway)
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
        XCTAssertEqual(pending.elapsedSinceCandidateStart, 0.9, accuracy: 0.000_001)
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
        XCTAssertEqual(reached.elapsedSinceCandidateStart, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(reached.requiredThreshold, 0.6)
        XCTAssertEqual(reached.reason, .thresholdReached)
    }

    func testDiagnosticResultReportsCandidateResetAndUnavailable() {
        var machine = AttentionStateMachine()

        _ = machine.applyWithDiagnostics(sample(.away, at: 0.2))
        let reset = machine.applyWithDiagnostics(sample(.noFace, at: 0.3))
        let unavailable = machine.applyWithDiagnostics(sample(.ambiguous, at: 0.4))

        XCTAssertEqual(reset.rawSignal, .noFace)
        XCTAssertEqual(reset.previousState, .facing)
        XCTAssertEqual(reset.nextState, .facing)
        XCTAssertEqual(reset.candidateSignal, .noFace)
        XCTAssertEqual(reset.candidateStartedAt, 0.3)
        XCTAssertEqual(reset.requiredThreshold, 1.0)
        XCTAssertEqual(reset.reason, .candidateReset)

        XCTAssertEqual(unavailable.rawSignal, .ambiguous)
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

    private func unsafeSignals() -> [RawAttentionSignal] {
        [
            .ambiguous,
            .unknown,
            .uncalibrated,
            .cameraPermissionDenied,
            .cameraUnavailable
        ]
    }
}

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

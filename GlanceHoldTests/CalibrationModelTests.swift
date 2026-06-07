import XCTest
@testable import GlanceHold

final class CalibrationModelTests: XCTestCase {
    func testHighCalibrationIsAccepted() {
        let result = CalibrationModel.evaluate(samples: stableSamples(spread: 0.4), existing: nil)

        guard case let .accepted(snapshot) = result else {
            return XCTFail("Expected accepted high calibration, got \(result)")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(snapshot.neutralPose.yawDegrees, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.pitchDegrees, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.rollDegrees, 0.0, accuracy: 0.001)
    }

    func testMarginalCalibrationWithoutPreviousCalibrationIsAccepted() {
        let result = CalibrationModel.evaluate(samples: stableSamples(spread: 2.0), existing: nil)

        guard case let .accepted(snapshot) = result else {
            return XCTFail("Expected accepted marginal calibration, got \(result)")
        }

        XCTAssertEqual(snapshot.quality, .marginal)
    }

    func testNoisyStartupCalibrationAcceptsBestStableWindow() {
        let samples = [
            pose(yaw: -10.0, pitch: 5.0, roll: 1.0, time: 0.0),
            pose(yaw: 8.0, pitch: -4.0, roll: -1.0, time: 0.1),
            pose(yaw: 0.2, pitch: -0.1, roll: 0.1, time: 0.2),
            pose(yaw: 0.4, pitch: 0.0, roll: -0.1, time: 0.3),
            pose(yaw: 0.3, pitch: 0.1, roll: 0.0, time: 0.4)
        ]

        let result = CalibrationModel.evaluate(samples: samples, existing: nil)

        guard case let .accepted(snapshot) = result else {
            return XCTFail("Expected noisy startup samples to use the stable window, got \(result)")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(snapshot.neutralPose.yawDegrees, 0.3, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.pitchDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.rollDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.time, 0.4, accuracy: 0.001)
    }

    func testCalibrationFailsWhenNoStableContiguousWindowExists() {
        let samples = [
            pose(yaw: -10.0, pitch: 4.0, time: 0.0),
            pose(yaw: -3.0, pitch: -4.0, time: 0.1),
            pose(yaw: 4.0, pitch: 4.0, time: 0.2),
            pose(yaw: 11.0, pitch: -4.0, time: 0.3),
            pose(yaw: 18.0, pitch: 4.0, time: 0.4)
        ]

        XCTAssertEqual(CalibrationModel.evaluate(samples: samples, existing: nil), .failed(previous: nil))
    }

    func testFailedCalibrationPreservesPreviousCalibration() {
        let previous = snapshot(quality: .high)
        let result = CalibrationModel.evaluate(samples: [], existing: previous)

        XCTAssertEqual(result, .failed(previous: previous))
    }

    func testMarginalCandidateOverHighExistingRequiresReplacementConfirmation() {
        let previous = snapshot(quality: .high)
        let result = CalibrationModel.evaluate(samples: stableSamples(spread: 2.0), existing: previous)

        guard case let .needsReplacementConfirmation(candidate, existing) = result else {
            return XCTFail("Expected replacement confirmation, got \(result)")
        }

        XCTAssertEqual(candidate.quality, .marginal)
        XCTAssertEqual(existing, previous)
    }

    func testReplacementDecisionKeepsCurrentByDefaultOrUsesNewExplicitly() {
        let existing = snapshot(quality: .high)
        let candidate = snapshot(quality: .marginal, yaw: 3.0)

        XCTAssertEqual(
            CalibrationModel.resolveReplacement(candidate: candidate, existing: existing, decision: .keepCurrent),
            existing
        )
        XCTAssertEqual(
            CalibrationModel.resolveReplacement(candidate: candidate, existing: existing, decision: .useNew),
            candidate
        )
    }

    func testClassifierMapsPoseThresholdsToRawAttentionSignals() {
        let settings = AttentionSettings.defaults.withCalibration(snapshot(quality: .high))
        let classifier = CalibratedAttentionClassifier(settings: settings)

        XCTAssertEqual(classifier.classify(.pose(pose(yaw: 19.0, pitch: 0.0))), .away)
        XCTAssertEqual(classifier.classify(.pose(pose(yaw: 0.0, pitch: 19.0))), .away)
        XCTAssertEqual(classifier.classify(.pose(pose(yaw: 8.0, pitch: 6.0))), .facing)
        XCTAssertEqual(classifier.classify(.noFace), .noFace)
        XCTAssertEqual(classifier.classify(.ambiguous), .ambiguous)
    }

    func testClassifierWithoutCalibrationIsUncalibrated() {
        let classifier = CalibratedAttentionClassifier(settings: .defaults)

        XCTAssertEqual(classifier.classify(.pose(pose(yaw: 0.0, pitch: 0.0))), .uncalibrated)
    }

    private func stableSamples(spread: Double) -> [PoseSample] {
        [
            pose(yaw: 0.0, pitch: 0.0, time: 1.0),
            pose(yaw: spread, pitch: spread, time: 2.0),
            pose(yaw: spread / 2.0, pitch: spread / 2.0, time: 3.0)
        ]
    }

    private func snapshot(quality: CalibrationQuality, yaw: Double = 0.0) -> CalibrationSnapshot {
        CalibrationSnapshot(
            neutralPose: pose(yaw: yaw, pitch: 0.0),
            quality: quality,
            createdAt: Date(timeIntervalSince1970: 10.0)
        )
    }

    private func pose(yaw: Double, pitch: Double, roll: Double = 0.0, time: TimeInterval = 0.0) -> PoseSample {
        PoseSample(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll, time: time)
    }
}

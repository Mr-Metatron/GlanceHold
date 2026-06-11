import XCTest
@testable import GlanceHold

final class CalibrationModelTests: XCTestCase {
    func testHighCalibrationIsAccepted() {
        let evaluation = CalibrationModel.evaluateDetailed(samples: stableSamples(spread: 0.4), existing: nil)

        guard case let .accepted(snapshot) = evaluation.result else {
            return XCTFail("Expected accepted high calibration, got \(evaluation.result)")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(snapshot.neutralPose.yawDegrees, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.pitchDegrees, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.rollDegrees, 0.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(evaluation.diagnostics.selectedWindowSampleCount, 5)
        XCTAssertGreaterThanOrEqual(evaluation.diagnostics.selectedWindowDurationSeconds ?? 0.0, 1.0)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSpreadDegrees ?? -1.0, 0.4, accuracy: 0.001)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowQuality, .high)
        XCTAssertNil(evaluation.diagnostics.failureReason)
    }

    func testMarginalCalibrationWithoutPreviousCalibrationIsAccepted() {
        let evaluation = CalibrationModel.evaluateDetailed(samples: stableSamples(spread: 2.0), existing: nil)

        guard case let .accepted(snapshot) = evaluation.result else {
            return XCTFail("Expected accepted marginal calibration, got \(evaluation.result)")
        }

        XCTAssertEqual(snapshot.quality, .marginal)
        XCTAssertGreaterThanOrEqual(evaluation.diagnostics.selectedWindowSampleCount, 5)
        XCTAssertGreaterThanOrEqual(evaluation.diagnostics.selectedWindowDurationSeconds ?? 0.0, 1.0)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSpreadDegrees ?? -1.0, 2.0, accuracy: 0.001)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowQuality, .marginal)
        XCTAssertNil(evaluation.diagnostics.failureReason)
    }

    func testNoisyStartupCalibrationAcceptsBestStableWindow() {
        let samples = [
            pose(yaw: -10.0, pitch: 5.0, roll: 1.0, time: 0.0),
            pose(yaw: 8.0, pitch: -4.0, roll: -1.0, time: 0.1),
            pose(yaw: 0.0, pitch: -0.2, roll: 0.1, time: 0.2),
            pose(yaw: 0.2, pitch: -0.1, roll: -0.1, time: 0.45),
            pose(yaw: 0.4, pitch: 0.0, roll: 0.0, time: 0.7),
            pose(yaw: 0.6, pitch: 0.1, roll: 0.1, time: 0.95),
            pose(yaw: 0.8, pitch: 0.2, roll: -0.1, time: 1.2)
        ]

        let result = CalibrationModel.evaluate(samples: samples, existing: nil)

        guard case let .accepted(snapshot) = result else {
            return XCTFail("Expected noisy startup samples to use the stable window, got \(result)")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(snapshot.neutralPose.yawDegrees, 0.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.pitchDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.rollDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.neutralPose.time, 1.2, accuracy: 0.001)
    }

    func testCalibrationRejectsLowSpreadWindowWithFewerThanFiveSamples() {
        let evaluation = CalibrationModel.evaluateDetailed(
            samples: microWindowSamples(count: 4, spread: 0.2),
            existing: nil
        )

        XCTAssertEqual(evaluation.result, .failed(previous: nil))
        XCTAssertEqual(evaluation.diagnostics.inputSampleCount, 4)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSampleCount, 0)
        XCTAssertNil(evaluation.diagnostics.selectedWindowDurationSeconds)
        XCTAssertNil(evaluation.diagnostics.selectedWindowSpreadDegrees)
        XCTAssertNil(evaluation.diagnostics.selectedWindowQuality)
        XCTAssertEqual(evaluation.diagnostics.failureReason?.rawValue, "notEnoughPoseSamples")
    }

    func testCalibrationRejectsLowSpreadWindowShorterThanMinimumDuration() {
        let evaluation = CalibrationModel.evaluateDetailed(
            samples: shortStableSamples(count: 5, spread: 0.2, start: 0.0, end: 0.8),
            existing: nil
        )

        XCTAssertEqual(evaluation.result, .failed(previous: nil))
        XCTAssertEqual(evaluation.diagnostics.inputSampleCount, 5)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSampleCount, 0)
        XCTAssertNil(evaluation.diagnostics.selectedWindowDurationSeconds)
        XCTAssertNil(evaluation.diagnostics.selectedWindowSpreadDegrees)
        XCTAssertNil(evaluation.diagnostics.selectedWindowQuality)
        XCTAssertEqual(evaluation.diagnostics.failureReason?.rawValue, "stableWindowTooShort")
    }

    func testCalibrationIgnoresInvalidMicroWindowsBeforeRankingValidWindow() {
        let samples = [
            pose(yaw: 10.0, pitch: 10.0, time: 0.0),
            pose(yaw: 10.1, pitch: 10.1, time: 0.1),
            pose(yaw: 10.0, pitch: 10.0, time: 0.2),
            pose(yaw: 9.9, pitch: 9.9, time: 0.3),
            pose(yaw: 0.0, pitch: -0.2, time: 1.0),
            pose(yaw: 0.2, pitch: -0.1, time: 1.25),
            pose(yaw: 0.4, pitch: 0.0, time: 1.5),
            pose(yaw: 0.6, pitch: 0.1, time: 1.75),
            pose(yaw: 0.8, pitch: 0.2, time: 2.0)
        ]

        let evaluation = CalibrationModel.evaluateDetailed(samples: samples, existing: nil)

        guard case let .accepted(snapshot) = evaluation.result else {
            return XCTFail("Expected valid stable window to be selected, got \(evaluation.result)")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(snapshot.neutralPose.yawDegrees, 0.4, accuracy: 0.001)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSampleCount, 5)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowDurationSeconds ?? -1.0, 1.0, accuracy: 0.001)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowSpreadDegrees ?? -1.0, 0.8, accuracy: 0.001)
        XCTAssertEqual(evaluation.diagnostics.selectedWindowQuality, .high)
        XCTAssertNil(evaluation.diagnostics.failureReason)
    }

    func testMarginalCalibrationUsesSameMinimumWindowGates() {
        let tooFewSamples = CalibrationModel.evaluateDetailed(
            samples: microWindowSamples(count: 4, spread: 2.0),
            existing: nil
        )
        let tooShortSamples = CalibrationModel.evaluateDetailed(
            samples: shortStableSamples(count: 5, spread: 2.0, start: 0.0, end: 0.8),
            existing: nil
        )
        let validSamples = CalibrationModel.evaluateDetailed(samples: stableSamples(spread: 2.0), existing: nil)

        XCTAssertEqual(tooFewSamples.result, .failed(previous: nil))
        XCTAssertEqual(tooFewSamples.diagnostics.failureReason?.rawValue, "notEnoughPoseSamples")
        XCTAssertEqual(tooShortSamples.result, .failed(previous: nil))
        XCTAssertEqual(tooShortSamples.diagnostics.failureReason?.rawValue, "stableWindowTooShort")

        guard case let .accepted(snapshot) = validSamples.result else {
            return XCTFail("Expected valid marginal calibration, got \(validSamples.result)")
        }

        XCTAssertEqual(snapshot.quality, .marginal)
        XCTAssertGreaterThanOrEqual(validSamples.diagnostics.selectedWindowSampleCount, 5)
        XCTAssertGreaterThanOrEqual(validSamples.diagnostics.selectedWindowDurationSeconds ?? 0.0, 1.0)
        XCTAssertEqual(validSamples.diagnostics.selectedWindowSpreadDegrees ?? -1.0, 2.0, accuracy: 0.001)
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
        shortStableSamples(count: 5, spread: spread, start: 1.0, end: 2.0)
    }

    private func microWindowSamples(count: Int, spread: Double) -> [PoseSample] {
        shortStableSamples(count: count, spread: spread, start: 0.0, end: 0.3)
    }

    private func shortStableSamples(
        count: Int,
        spread: Double,
        start: TimeInterval,
        end: TimeInterval
    ) -> [PoseSample] {
        guard count > 1 else {
            return [pose(yaw: 0.0, pitch: 0.0, time: start)]
        }

        let timeStep = (end - start) / Double(count - 1)
        let poseStep = spread / Double(count - 1)

        return (0..<count).map { index in
            let offset = Double(index)
            return pose(
                yaw: poseStep * offset,
                pitch: poseStep * offset,
                time: start + timeStep * offset
            )
        }
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

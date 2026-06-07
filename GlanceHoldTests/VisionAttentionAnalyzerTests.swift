import XCTest
@testable import GlanceHold

final class VisionAttentionAnalyzerTests: XCTestCase {
    func testObservationHelpersMapNoFaceAndMissingAnglesSafely() {
        XCTAssertEqual(VisionAttentionObservation.noFace(time: 1.0), .noFace(time: 1.0))
        XCTAssertEqual(
            LiveVisionAttentionAnalyzer.observation(yawRadians: nil, pitchRadians: 0.0, rollRadians: 0.0, time: 2.0),
            .ambiguous(time: 2.0)
        )
        XCTAssertEqual(
            LiveVisionAttentionAnalyzer.observation(yawRadians: 0.0, pitchRadians: nil, rollRadians: 0.0, time: 2.0),
            .ambiguous(time: 2.0)
        )
    }

    func testObservationHelperAllowsMissingRollForYawPitchClassifier() {
        let observation = LiveVisionAttentionAnalyzer.observation(
            yawRadians: .pi / 6.0,
            pitchRadians: -.pi / 8.0,
            rollRadians: nil,
            time: 4.0
        )

        guard case .pose(let sample) = observation else {
            return XCTFail("Expected pose when yaw and pitch are present")
        }

        XCTAssertEqual(sample.yawDegrees, 30.0, accuracy: 0.001)
        XCTAssertEqual(sample.pitchDegrees, -22.5, accuracy: 0.001)
        XCTAssertEqual(sample.rollDegrees, 0.0, accuracy: 0.001)
        XCTAssertEqual(sample.time, 4.0)
    }

    func testObservationHelperConvertsRadiansToScalarPoseDegrees() {
        let observation = LiveVisionAttentionAnalyzer.observation(
            yawRadians: .pi / 2.0,
            pitchRadians: .pi / 4.0,
            rollRadians: -.pi / 4.0,
            time: 3.0
        )

        guard case .pose(let sample) = observation else {
            return XCTFail("Expected scalar pose observation")
        }

        XCTAssertEqual(sample.yawDegrees, 90.0, accuracy: 0.001)
        XCTAssertEqual(sample.pitchDegrees, 45.0, accuracy: 0.001)
        XCTAssertEqual(sample.rollDegrees, -45.0, accuracy: 0.001)
        XCTAssertEqual(sample.time, 3.0)
    }
}

import XCTest
@testable import GlanceHold

final class MonitoringToggleControllerTests: XCTestCase {
    func testShortcutToggleUsesSameSafePrimaryActionPath() {
        XCTAssertEqual(
            MonitoringToggleController.resolveAction(for: state(status: .off, hasCalibration: true)),
            .enable
        )
        XCTAssertEqual(
            MonitoringToggleController.resolveAction(for: state(status: .facing, hasCalibration: true)),
            .disable
        )
        XCTAssertEqual(
            MonitoringToggleController.resolveAction(for: state(status: .off, hasCalibration: false)),
            .calibrate
        )
        XCTAssertEqual(
            MonitoringToggleController.resolveAction(for: state(status: .cameraPermissionDenied, hasCalibration: false)),
            .openCameraSettings
        )
        XCTAssertEqual(
            MonitoringToggleController.resolveAction(for: state(status: .requestingCameraPermission, hasCalibration: false)),
            .wait
        )
    }

    func testLifecycleCleanupPlanSeparatesUserDisableFromQuitTermination() {
        XCTAssertEqual(
            MonitoringToggleController.cleanupPlan(for: .userDisable),
            MonitoringLifecycleCleanupPlan(
                cancelPermissionRequest: true,
                stopPlaybackStatusUpdates: false,
                stopMonitoringToggleRequests: false,
                stopAttentionMonitor: true,
                stopPlaybackCoordinator: true,
                recordStoppedLastAction: true,
                terminateAfterCleanup: false
            )
        )
        XCTAssertEqual(
            MonitoringToggleController.cleanupPlan(for: .quit),
            MonitoringLifecycleCleanupPlan(
                cancelPermissionRequest: true,
                stopPlaybackStatusUpdates: true,
                stopMonitoringToggleRequests: true,
                stopAttentionMonitor: true,
                stopPlaybackCoordinator: true,
                recordStoppedLastAction: false,
                terminateAfterCleanup: true
            )
        )
    }

    private func state(status: MonitoringStatus, hasCalibration: Bool) -> GlanceHoldState {
        var settings = AttentionSettings.defaults
        settings.calibration = hasCalibration ? Self.calibration : nil
        return GlanceHoldState(status: status, settings: settings)
    }

    private static let calibration = CalibrationSnapshot(
        neutralPose: PoseSample(yawDegrees: 0, pitchDegrees: 0, rollDegrees: 0, time: 0),
        quality: .high,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

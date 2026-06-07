import XCTest
@testable import GlanceHold

final class GlanceHoldStateTests: XCTestCase {
    func testNewStateReportsOffVisibleStatusText() {
        let state = GlanceHoldState()

        XCTAssertEqual(state.status.visibleTitle, "Off")
        XCTAssertNil(state.playerStatus)
    }

    func testEnablingMonitoringWithoutPermissionResolutionDoesNotBecomeActive() {
        var state = GlanceHoldState()

        state.enableMonitoring()

        XCTAssertEqual(state.status.visibleTitle, "Camera Permission Needed")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testDisablingMonitoringReturnsVisibleStatusTextToOff() {
        var state = GlanceHoldState(status: .facing)

        state.disableMonitoring()

        XCTAssertEqual(state.status.visibleTitle, "Off")
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testModeSelectionReportsExactVisibleModeNames() {
        var state = GlanceHoldState()

        state.selectMode(.speedControl)
        XCTAssertEqual(state.mode.displayName, "Speed Control")

        state.selectMode(.pauseResume)
        XCTAssertEqual(state.mode.displayName, "Pause/Resume")
    }

    func testModeVocabularyIncludesRequiredPhrases() {
        let phrases = MonitoringMode.allCases.map(\.displayName)

        XCTAssertEqual(phrases, [
            "Speed Control",
            "Pause/Resume"
        ])
    }

    func testVisibleStatusVocabularyIncludesRequiredPhrases() {
        let phrases = MonitoringStatus.visibleVocabulary

        XCTAssertEqual(phrases, [
            "Off",
            "Camera Permission Needed",
            "Camera Permission Denied",
            "Camera Unavailable",
            "Needs Calibration",
            "Calibrating Facing Pose",
            "Calibration Failed",
            "Requesting Camera Permission",
            "Ready After Calibration",
            "Facing",
            "Looking Away",
            "No Face Detected",
            "Recovering",
            ["I", "INA Unavailable"].joined()
        ])
    }

    func testPlayerControlStatusVocabularyIncludesIINAStates() {
        let phrases = PlayerControlStatus.visibleVocabulary

        XCTAssertEqual(phrases, [
            "IINA Unavailable",
            "IINA Bridge Waiting",
            "IINA Idle",
            "IINA Paused",
            "IINA Playing",
            "IINA Not Controllable"
        ])
    }

    func testAttentionStatusAndPlayerStatusCanCoexist() {
        let state = GlanceHoldState(status: .facing, playerStatus: .unavailable)

        XCTAssertEqual(state.status.visibleTitle, "Facing")
        XCTAssertEqual(state.playerStatus?.visibleTitle, "IINA Unavailable")
        XCTAssertTrue(state.isMonitoringActive)
    }

    func testIINAUnavailableDetailExplainsMonitoringCanContinue() {
        XCTAssertEqual(
            PlayerControlStatus.unavailable.detailText,
            "Attention monitoring can continue while playback control waits for controllable IINA state."
        )
    }

    func testSetupNeededStatusUsesNeutralBridgeWaitingCopy() {
        XCTAssertEqual(PlayerControlStatus.setupNeeded.visibleTitle, "IINA Bridge Waiting")
        XCTAssertTrue(PlayerControlStatus.setupNeeded.detailText.contains("IINA plugin"))
        XCTAssertTrue(PlayerControlStatus.setupNeeded.detailText.contains("Start IINA"))
        XCTAssertTrue(PlayerControlStatus.setupNeeded.detailText.contains("load a video"))
    }

    func testPhase3StatusTitlesAreExact() {
        XCTAssertEqual(MonitoringStatus.cameraUnavailable.visibleTitle, "Camera Unavailable")
        XCTAssertEqual(MonitoringStatus.needsCalibration.visibleTitle, "Needs Calibration")
        XCTAssertEqual(MonitoringStatus.calibratingFacingPose.visibleTitle, "Calibrating Facing Pose")
        XCTAssertEqual(MonitoringStatus.calibrationFailed(previousKept: true).visibleTitle, "Calibration Failed")
        XCTAssertEqual(MonitoringStatus.readyAfterCalibration.visibleTitle, "Ready After Calibration")
        XCTAssertEqual(MonitoringStatus.facing.visibleTitle, "Facing")
        XCTAssertEqual(MonitoringStatus.lookingAway.visibleTitle, "Looking Away")
        XCTAssertEqual(MonitoringStatus.noFaceDetected.visibleTitle, "No Face Detected")
        XCTAssertEqual(MonitoringStatus.recovering.visibleTitle, "Recovering")
    }

    func testPendingAndFailureStatusesAreNotMonitoringActive() {
        XCTAssertFalse(GlanceHoldState(status: .requestingCameraPermission).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .cameraPermissionDenied).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .cameraUnavailable).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .needsCalibration).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .calibratingFacingPose).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .calibrationFailed(previousKept: true)).isMonitoringActive)
    }

    func testPhase3DetailCopyIsStable() {
        XCTAssertEqual(
            MonitoringStatus.cameraPermissionDenied.detailText,
            "Camera permission is denied. Allow camera access in System Settings, then enable monitoring again."
        )
        XCTAssertEqual(
            MonitoringStatus.cameraUnavailable.detailText,
            "Camera is unavailable. Check camera access or close other apps using the camera, then try again."
        )
        XCTAssertEqual(
            MonitoringStatus.calibrationFailed(previousKept: true).detailText,
            "Calibration failed because no stable face was detected. Your previous calibration was kept."
        )
        XCTAssertEqual(
            MonitoringStatus.calibrationFailed(previousKept: false).detailText,
            "Calibration failed because no stable face was detected. Try again while facing the screen."
        )
        XCTAssertEqual(
            MonitoringStatus.readyAfterMarginalCalibration.detailText,
            "Recalibration recommended. Monitoring can continue with the current calibration."
        )
        XCTAssertEqual(
            MonitoringStatus.needsCalibration.detailText,
            "Calibrate your facing-screen pose before monitoring can use camera signals. Camera access starts only after you choose calibration or monitoring."
        )
    }

    func testPrimaryActionsCoverCalibrationPermissionAndMonitoringStates() {
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .off, hasCalibration: false), .calibrate)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .needsCalibration, hasCalibration: false), .calibrate)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .readyAfterCalibration, hasCalibration: true), .enable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .facing, hasCalibration: true), .disable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .cameraPermissionDenied, hasCalibration: false), .openCameraSettings)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .calibratingFacingPose, hasCalibration: false), .wait)

        XCTAssertEqual(GlanceHoldPrimaryAction.calibrate.title, "Calibrate Facing Pose")
        XCTAssertEqual(GlanceHoldPrimaryAction.recalibrate.title, "Recalibrate Facing Pose")
        XCTAssertEqual(GlanceHoldPrimaryAction.resetCalibration.title, "Reset Calibration")
    }

    func testMenuCopyIncludesTuningCalibrationPrivacyAndConfirmationVocabulary() {
        XCTAssertEqual(GlanceHoldMenuCopy.tuningSectionTitle, "Tuning")
        XCTAssertEqual(GlanceHoldMenuCopy.sensitivityLabel, "Head Turn Sensitivity")
        XCTAssertEqual(GlanceHoldMenuCopy.speedControlAwayDelayLabel, "Speed Control Away Delay")
        XCTAssertEqual(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel, "Pause/Resume Away Delay")
        XCTAssertEqual(GlanceHoldMenuCopy.recoveryDelayLabel, "Recovery Delay")
        XCTAssertEqual(GlanceHoldMenuCopy.privacyNote, "Camera stays on this Mac. Frames are not saved or uploaded.")
        XCTAssertEqual(GlanceHoldMenuCopy.marginalReplacementPrompt, "The new calibration is usable but less stable than the current one. Keep the current calibration or use the new one?")
        XCTAssertEqual(GlanceHoldMenuCopy.keepCurrentCalibrationButton, "Keep Current Calibration")
        XCTAssertEqual(GlanceHoldMenuCopy.useNewCalibrationButton, "Use New Calibration")
    }

    func testMonitorStatesMapToVisibleStatusVocabulary() {
        XCTAssertEqual(MonitoringStatus(monitorState: .off), .off)
        XCTAssertEqual(MonitoringStatus(monitorState: .needsCalibration), .needsCalibration)
        XCTAssertEqual(MonitoringStatus(monitorState: .calibrating), .calibratingFacingPose)
        XCTAssertEqual(MonitoringStatus(monitorState: .ready), .readyAfterCalibration)
        XCTAssertEqual(MonitoringStatus(monitorState: .facing), .facing)
        XCTAssertEqual(MonitoringStatus(monitorState: .lookingAway), .lookingAway)
        XCTAssertEqual(MonitoringStatus(monitorState: .noFaceDetected), .noFaceDetected)
        XCTAssertEqual(MonitoringStatus(monitorState: .recovering), .recovering)
        XCTAssertEqual(MonitoringStatus(monitorState: .cameraPermissionDenied), .cameraPermissionDenied)
        XCTAssertEqual(MonitoringStatus(monitorState: .cameraUnavailable), .cameraUnavailable)
        XCTAssertEqual(MonitoringStatus(monitorState: .calibrationFailed(previousKept: true)), .calibrationFailed(previousKept: true))
        XCTAssertEqual(MonitoringStatus(monitorState: .calibrationFailed(previousKept: false)), .calibrationFailed(previousKept: false))
    }
}

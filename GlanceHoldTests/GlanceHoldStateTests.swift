import XCTest
@testable import GlanceHold

final class GlanceHoldStateTests: XCTestCase {
    func testNewStateReportsOffVisibleStatusText() {
        let state = GlanceHoldState()

        XCTAssertEqual(state.status.visibleTitle, "Off")
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
        let phrases = MonitoringStatus.allCases.map(\.visibleTitle)

        XCTAssertEqual(phrases, [
            "Off",
            "Camera Permission Needed",
            "Camera Permission Denied",
            "Requesting Camera Permission",
            "Ready After Calibration",
            "Facing",
            "Looking Away",
            "No Face Detected",
            "Recovering",
            ["I", "INA Unavailable"].joined()
        ])
    }

    func testPendingAndPermissionDeniedStatusesAreNotMonitoringActive() {
        XCTAssertFalse(GlanceHoldState(status: .requestingCameraPermission).isMonitoringActive)
        XCTAssertFalse(GlanceHoldState(status: .cameraPermissionDenied).isMonitoringActive)
    }

    func testPermissionRecoveryAndUnavailableCopyAreStable() {
        XCTAssertEqual(
            MonitoringStatus.cameraPermissionDenied.detailText,
            "Camera permission is denied. Allow camera access in System Settings, then enable monitoring again."
        )
        XCTAssertEqual(
            MonitoringStatus.iinaUnavailable.detailText,
            "Monitoring cannot start yet because IINA is unavailable."
        )
    }
}

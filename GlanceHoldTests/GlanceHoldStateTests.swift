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

    func testVisibleStatusVocabularyIncludesRequiredPhrases() {
        let phrases = MonitoringStatus.allCases.map(\.visibleTitle)

        XCTAssertEqual(phrases, [
            "Off",
            "Camera Permission Needed",
            "Ready After Calibration",
            "Facing",
            "Looking Away",
            "No Face Detected",
            "Recovering",
            "IINA Unavailable"
        ])
    }
}

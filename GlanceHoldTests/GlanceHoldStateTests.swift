import XCTest
@testable import GlanceHold

final class GlanceHoldStateTests: XCTestCase {
    func testDiagnosticSettingsDefaultDisabledAndPersistedTogglesRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GlanceHoldStateTests.diagnostics.\(UUID().uuidString)"))
        let store = UserDefaultsDiagnosticSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .disabled)

        try store.save(DiagnosticSettings(isEnabled: true))
        XCTAssertTrue(UserDefaultsDiagnosticSettingsStore(defaults: defaults).load().isEnabled)

        try store.save(.disabled)
        XCTAssertFalse(UserDefaultsDiagnosticSettingsStore(defaults: defaults).load().isEnabled)
    }

    func testAttentionCalibrationResetDoesNotClearDiagnosticMode() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GlanceHoldStateTests.independent.\(UUID().uuidString)"))
        let attentionStore = UserDefaultsAttentionSettingsStore(defaults: defaults)
        let diagnosticStore = UserDefaultsDiagnosticSettingsStore(defaults: defaults)

        try diagnosticStore.save(DiagnosticSettings(isEnabled: true))
        try attentionStore.reset()

        XCTAssertTrue(diagnosticStore.load().isEnabled)
    }

    func testNewStateReportsOffVisibleStatusText() {
        let state = GlanceHoldState()

        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringOffTitle))
        XCTAssertNil(state.playerStatus)
        XCTAssertNil(state.lastAction)
        XCTAssertNil(state.lastActionMenuText)
    }

    func testEnablingMonitoringWithoutPermissionResolutionDoesNotBecomeActive() {
        var state = GlanceHoldState()

        state.enableMonitoring()

        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringCameraPermissionNeededTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testDisablingMonitoringReturnsVisibleStatusTextToOff() {
        var state = GlanceHoldState(status: .facing)

        state.disableMonitoring()

        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringOffTitle))
        XCTAssertFalse(state.isMonitoringActive)
    }

    func testUserRequestedStopRecordsGenericStoppedLastAction() {
        var state = GlanceHoldState(status: .facing, lastAction: .heldSpeedAtOne)

        state.stopMonitoringAfterUserRequest()

        XCTAssertEqual(state.status, .off)
        XCTAssertEqual(state.lastAction, .stoppedMonitoring)
    }

    func testManualPlaybackTakeoverStopReturnsPrimaryActionToEnableMonitoring() {
        var state = GlanceHoldState(status: .facing, playerStatus: .playing)

        state.stopMonitoringAfterManualPlayerTakeover()

        XCTAssertEqual(state.status, .off)
        XCTAssertFalse(state.isMonitoringActive)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: state.status, hasCalibration: true), .enable)
        XCTAssertEqual(state.playerStatus, .playing)
        XCTAssertEqual(state.lastAction, .manualPauseDetected)
    }

    func testReadinessAndPlayerStatusChurnDoNotRecordLastAction() {
        var state = GlanceHoldState()

        state.apply(monitorState: .needsCalibration)
        state.apply(monitorState: .facing)
        state.apply(playerControlState: .unavailable)
        state.apply(playerControlState: PlaybackCoordinatorState(isPlayerControllable: true, playerSnapshot: .playing(speed: 1.25)))

        XCTAssertNil(state.lastAction)
    }

    func testNewMonitoringSessionClearsPriorLastAction() {
        var state = GlanceHoldState(status: .off)
        state.recordLastAction(.restoredSpeed(2.0))

        state.enableMonitoring()

        XCTAssertNil(state.lastAction)
        XCTAssertNil(state.lastActionMenuText)
    }

    func testLastActionMenuCopyUsesCompactPlaybackAndSafetyText() {
        var state = GlanceHoldState()

        state.recordLastAction(.heldSpeedAtOne)
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.heldSpeedAtOne.visibleText())
        )

        state.recordLastAction(.restoredSpeed(2.0))
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.restoredSpeed(2.0).visibleText())
        )

        state.recordLastAction(.restoredSpeed(1.25))
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.restoredSpeed(1.25).visibleText())
        )

        state.recordLastAction(.pausedByGlanceHold)
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.pausedByGlanceHold.visibleText())
        )

        state.recordLastAction(.resumedPlayback)
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.resumedPlayback.visibleText())
        )

        state.recordLastAction(.manualPauseDetected)
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.manualPauseDetected.visibleText())
        )

        state.recordLastAction(.stoppedMonitoring)
        XCTAssertEqual(
            state.lastActionMenuText,
            GlanceHoldStrings.format(.menuLastActionFormat, LastAction.stoppedMonitoring.visibleText())
        )
    }

    func testModeSelectionReportsExactVisibleModeNames() {
        var state = GlanceHoldState()

        state.selectMode(.speedControl)
        XCTAssertEqual(state.mode.displayName, GlanceHoldStrings.text(.modeSpeedControl))

        state.selectMode(.pauseResume)
        XCTAssertEqual(state.mode.displayName, GlanceHoldStrings.text(.modePauseResume))
    }

    func testModeVocabularyIncludesRequiredPhrases() {
        let phrases = MonitoringMode.allCases.map(\.displayName)

        XCTAssertEqual(phrases, [
            GlanceHoldStrings.text(.modeSpeedControl),
            GlanceHoldStrings.text(.modePauseResume)
        ])
    }

    func testVisibleStatusVocabularyIncludesRequiredPhrases() {
        let phrases = MonitoringStatus.visibleVocabulary

        XCTAssertEqual(phrases, [
            GlanceHoldStrings.text(.monitoringOffTitle),
            GlanceHoldStrings.text(.monitoringCameraPermissionNeededTitle),
            GlanceHoldStrings.text(.monitoringCameraPermissionDeniedTitle),
            GlanceHoldStrings.text(.monitoringCameraUnavailableTitle),
            GlanceHoldStrings.text(.monitoringNeedsCalibrationTitle),
            GlanceHoldStrings.text(.monitoringCalibratingFacingPoseTitle),
            GlanceHoldStrings.text(.monitoringCalibrationFailedTitle),
            GlanceHoldStrings.text(.monitoringRequestingCameraPermissionTitle),
            GlanceHoldStrings.text(.monitoringReadyAfterCalibrationTitle),
            GlanceHoldStrings.text(.monitoringFacingTitle),
            GlanceHoldStrings.text(.monitoringLookingAwayTitle),
            GlanceHoldStrings.text(.monitoringNoFaceDetectedTitle),
            GlanceHoldStrings.text(.monitoringRecoveringTitle),
            GlanceHoldStrings.text(.monitoringIINAUnavailableTitle)
        ])
    }

    func testPlayerControlStatusVocabularyIncludesIINAStates() {
        let phrases = PlayerControlStatus.visibleVocabulary

        XCTAssertEqual(phrases, [
            GlanceHoldStrings.text(.playerUnavailableTitle),
            GlanceHoldStrings.text(.playerSetupNeededTitle),
            GlanceHoldStrings.text(.playerIdleTitle),
            GlanceHoldStrings.text(.playerPausedTitle),
            GlanceHoldStrings.text(.playerPlayingTitle),
            GlanceHoldStrings.text(.playerNotControllableTitle)
        ])
    }

    func testAttentionStatusAndPlayerStatusCanCoexist() {
        let state = GlanceHoldState(status: .facing, playerStatus: .unavailable)

        XCTAssertEqual(state.status.visibleTitle, GlanceHoldStrings.text(.monitoringFacingTitle))
        XCTAssertEqual(state.playerStatus?.visibleTitle, GlanceHoldStrings.text(.playerUnavailableTitle))
        XCTAssertTrue(state.isMonitoringActive)
    }

    func testIINAUnavailableDetailExplainsMonitoringCanContinue() {
        XCTAssertEqual(
            PlayerControlStatus.unavailable.detailText,
            GlanceHoldStrings.text(.playerUnavailableDetail)
        )
    }

    func testSetupNeededStatusUsesNeutralBridgeWaitingCopy() {
        XCTAssertEqual(PlayerControlStatus.setupNeeded.visibleTitle, GlanceHoldStrings.text(.playerSetupNeededTitle))
        XCTAssertEqual(PlayerControlStatus.setupNeeded.detailText, GlanceHoldStrings.text(.playerSetupNeededDetail))
        XCTAssertFalse(PlayerControlStatus.setupNeeded.detailText.isEmpty)
    }

    func testPhase3StatusTitlesAreExact() {
        XCTAssertEqual(MonitoringStatus.cameraUnavailable.visibleTitle, GlanceHoldStrings.text(.monitoringCameraUnavailableTitle))
        XCTAssertEqual(MonitoringStatus.needsCalibration.visibleTitle, GlanceHoldStrings.text(.monitoringNeedsCalibrationTitle))
        XCTAssertEqual(MonitoringStatus.calibratingFacingPose.visibleTitle, GlanceHoldStrings.text(.monitoringCalibratingFacingPoseTitle))
        XCTAssertEqual(MonitoringStatus.calibrationFailed(previousKept: true).visibleTitle, GlanceHoldStrings.text(.monitoringCalibrationFailedTitle))
        XCTAssertEqual(MonitoringStatus.readyAfterCalibration.visibleTitle, GlanceHoldStrings.text(.monitoringReadyAfterCalibrationTitle))
        XCTAssertEqual(MonitoringStatus.facing.visibleTitle, GlanceHoldStrings.text(.monitoringFacingTitle))
        XCTAssertEqual(MonitoringStatus.lookingAway.visibleTitle, GlanceHoldStrings.text(.monitoringLookingAwayTitle))
        XCTAssertEqual(MonitoringStatus.noFaceDetected.visibleTitle, GlanceHoldStrings.text(.monitoringNoFaceDetectedTitle))
        XCTAssertEqual(MonitoringStatus.recovering.visibleTitle, GlanceHoldStrings.text(.monitoringRecoveringTitle))
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
            GlanceHoldStrings.text(.monitoringCameraPermissionDeniedDetail)
        )
        XCTAssertEqual(
            MonitoringStatus.cameraUnavailable.detailText,
            GlanceHoldStrings.text(.monitoringCameraUnavailableDetail)
        )
        XCTAssertEqual(
            MonitoringStatus.calibrationFailed(previousKept: true).detailText,
            GlanceHoldStrings.text(.monitoringCalibrationFailedPreviousKeptDetail)
        )
        XCTAssertEqual(
            MonitoringStatus.calibrationFailed(previousKept: false).detailText,
            GlanceHoldStrings.text(.monitoringCalibrationFailedRetryDetail)
        )
        XCTAssertEqual(
            MonitoringStatus.readyAfterMarginalCalibration.detailText,
            GlanceHoldStrings.text(.monitoringReadyAfterMarginalCalibrationDetail)
        )
        XCTAssertEqual(
            MonitoringStatus.needsCalibration.detailText,
            GlanceHoldStrings.text(.monitoringCalibrationNeededDetail)
        )
    }

    func testPrimaryActionsCoverCalibrationPermissionAndMonitoringStates() {
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .off, hasCalibration: false), .calibrate)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .needsCalibration, hasCalibration: false), .calibrate)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .readyAfterCalibration, hasCalibration: true), .enable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .facing, hasCalibration: true), .disable)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .cameraPermissionDenied, hasCalibration: false), .openCameraSettings)
        XCTAssertEqual(GlanceHoldPrimaryAction.resolve(for: .calibratingFacingPose, hasCalibration: false), .wait)

        XCTAssertEqual(GlanceHoldPrimaryAction.calibrate.title, GlanceHoldStrings.text(.actionCalibrate))
        XCTAssertEqual(GlanceHoldPrimaryAction.recalibrate.title, GlanceHoldStrings.text(.actionRecalibrate))
        XCTAssertEqual(GlanceHoldPrimaryAction.resetCalibration.title, GlanceHoldStrings.text(.actionResetCalibration))
    }

    func testMenuCopyIncludesTuningCalibrationPrivacyAndConfirmationVocabulary() {
        XCTAssertEqual(GlanceHoldMenuCopy.tuningSectionTitle, GlanceHoldStrings.text(.tuningSection))
        XCTAssertEqual(GlanceHoldMenuCopy.sensitivityLabel, GlanceHoldStrings.text(.tuningSensitivity))
        XCTAssertEqual(GlanceHoldMenuCopy.speedControlAwayDelayLabel, GlanceHoldStrings.text(.tuningSpeedControlAwayDelay))
        XCTAssertEqual(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel, GlanceHoldStrings.text(.tuningPauseResumeAwayDelay))
        XCTAssertEqual(GlanceHoldMenuCopy.recoveryDelayLabel, GlanceHoldStrings.text(.tuningRecoveryDelay))
        XCTAssertEqual(GlanceHoldMenuCopy.privacyNote, GlanceHoldStrings.text(.privacyNote))
        XCTAssertEqual(GlanceHoldMenuCopy.marginalReplacementPrompt, GlanceHoldStrings.text(.alertMarginalReplacementPrompt))
        XCTAssertEqual(GlanceHoldMenuCopy.keepCurrentCalibrationButton, GlanceHoldStrings.text(.alertKeepCurrentCalibration))
        XCTAssertEqual(GlanceHoldMenuCopy.useNewCalibrationButton, GlanceHoldStrings.text(.alertUseNewCalibration))
    }

    func testMonitorStatesMapToVisibleStatusVocabulary() {
        XCTAssertEqual(MonitoringStatus(monitorState: .off), .off)
        XCTAssertEqual(MonitoringStatus(monitorState: .needsCalibration), .needsCalibration)
        XCTAssertEqual(MonitoringStatus(monitorState: .calibrating), .calibratingFacingPose)
        XCTAssertEqual(MonitoringStatus(monitorState: .ready), .readyAfterCalibration)
        XCTAssertEqual(MonitoringStatus(monitorState: .monitoringPendingFirstSample), .facing)
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

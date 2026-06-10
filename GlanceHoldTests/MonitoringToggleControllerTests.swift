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

    func testCalibrationStartRequiresLifecycleCleanupWhenMonitoringOrRequestingPermission() {
        for status in [
            MonitoringStatus.requestingCameraPermission,
            .facing,
            .lookingAway,
            .noFaceDetected,
            .recovering,
            .iinaUnavailable
        ] {
            XCTAssertTrue(
                CalibrationStartController.requiresLifecycleCleanupBeforeStarting(
                    from: state(status: status, hasCalibration: true)
                ),
                "Expected cleanup before calibration from \(status)"
            )
        }

        for status in [
            MonitoringStatus.off,
            .cameraPermissionNeeded,
            .cameraPermissionDenied,
            .cameraUnavailable,
            .needsCalibration,
            .calibratingFacingPose,
            .calibrationFailed(previousKept: false),
            .readyAfterCalibration,
            .readyAfterMarginalCalibration
        ] {
            XCTAssertFalse(
                CalibrationStartController.requiresLifecycleCleanupBeforeStarting(
                    from: state(status: status, hasCalibration: true)
                ),
                "Did not expect cleanup before calibration from \(status)"
            )
        }

        let cleanupPlan = MonitoringToggleController.cleanupPlan(for: .userDisable)
        XCTAssertTrue(cleanupPlan.cancelPermissionRequest)
        XCTAssertTrue(cleanupPlan.stopAttentionMonitor)
        XCTAssertTrue(cleanupPlan.stopPlaybackCoordinator)
    }

    func testDiagnosticModeTogglePersistsBeforeRequestingRestart() throws {
        let store = FakeDiagnosticSettingsStore(settings: .disabled)
        let requester = FakeAppRestartRequester()
        requester.store = store

        try DiagnosticModeMenuAction.toggle(settingsStore: store, restartRequester: requester)

        XCTAssertEqual(store.savedSettings, [DiagnosticSettings(isEnabled: true)])
        XCTAssertEqual(requester.requestCount, 1)
        XCTAssertEqual(requester.events, ["restart"])
        XCTAssertEqual(store.events, ["load", "save:true", "restartObserved:true"])
    }

    func testDiagnosticModeToggleCanDisablePersistedModeAndRequestsOneRestart() throws {
        let store = FakeDiagnosticSettingsStore(settings: DiagnosticSettings(isEnabled: true))
        let requester = FakeAppRestartRequester()

        try DiagnosticModeMenuAction.toggle(settingsStore: store, restartRequester: requester)

        XCTAssertEqual(store.savedSettings, [.disabled])
        XCTAssertEqual(requester.requestCount, 1)
    }

    func testDiagnosticModeToggleReportsRestartFailureAfterPersistingSetting() throws {
        let store = FakeDiagnosticSettingsStore(settings: .disabled)
        let requester = FakeAppRestartRequester()
        requester.shouldFail = true
        var restartFailureCount = 0

        try DiagnosticModeMenuAction.toggle(
            settingsStore: store,
            restartRequester: requester,
            restartFailureHandler: {
                restartFailureCount += 1
            }
        )

        XCTAssertEqual(store.savedSettings, [DiagnosticSettings(isEnabled: true)])
        XCTAssertEqual(requester.requestCount, 1)
        XCTAssertEqual(restartFailureCount, 1)
    }

    func testAppSourceWiresDiagnosticModeRecorderAndMenuNearAboutQuit() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/GlanceHoldApp.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("let diagnosticSettingsStore = UserDefaultsDiagnosticSettingsStore()"))
        XCTAssertTrue(source.contains("let loadedDiagnosticSettings = diagnosticSettingsStore.load()"))
        XCTAssertTrue(source.contains("LiveDiagnosticRecorder(mode: loadedDiagnosticSettings.diagnosticMode)"))
        XCTAssertTrue(source.contains("diagnosticRecorder: diagnosticRecorder"))
        XCTAssertTrue(source.contains("restartRequester: LiveAppRestartRequester()"))
        XCTAssertTrue(source.contains("DiagnosticModeMenuAction.toggle"))

        let diagnosticRange = try XCTUnwrap(source.range(of: "DiagnosticModeMenuPresentation"))
        let aboutRange = try XCTUnwrap(source.range(of: "GlanceHoldStrings.text(.menuAbout)"))
        let quitRange = try XCTUnwrap(source.range(of: "GlanceHoldStrings.text(.menuQuit)"))
        XCTAssertLessThan(diagnosticRange.lowerBound, aboutRange.lowerBound)
        XCTAssertLessThan(aboutRange.lowerBound, quitRange.lowerBound)
    }

    func testLiveRestartRequesterOnlyTerminatesAfterSuccessfulRelaunch() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/AppRestartRequester.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("guard app != nil, error == nil else"))
        XCTAssertTrue(source.contains("onFailure()"))
        let relaunchGuardRange = try XCTUnwrap(source.range(of: "guard app != nil, error == nil else"))
        let terminateRange = try XCTUnwrap(source.range(of: "NSApplication.shared.terminate(nil)"))
        XCTAssertLessThan(relaunchGuardRange.lowerBound, terminateRange.lowerBound)
    }

    func testAppSourceDeduplicatesPlaybackSemanticsBeforeSendingAttentionState() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/GlanceHoldApp.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var playbackSemanticDeduper = PlaybackSemanticDeduper()"))
        XCTAssertTrue(source.contains("resetPlaybackSemanticDeduper(for: currentDiagnosticSession)"))
        XCTAssertTrue(source.contains("resetPlaybackSemanticDeduper(for: session)"))
        XCTAssertTrue(source.contains("playbackSemanticDeduper.endSession()"))
        XCTAssertTrue(source.contains("playbackSemanticDeduper.startSession(session.id)"))

        let dedupRange = try XCTUnwrap(source.range(of: "playbackSemanticDeduper.shouldEmit(attentionState)"))
        let sendRange = try XCTUnwrap(source.range(of: "sendAttentionState(attentionState, to: coordinator)"))
        XCTAssertLessThan(dedupRange.lowerBound, sendRange.lowerBound)
    }

    func testAppSourceCleansMonitoringLifecycleBeforeStartingCalibration() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/GlanceHoldApp.swift"), encoding: .utf8)
        let calibrationStart = try XCTUnwrap(source.range(of: "private func startCalibration"))
        let nextFunction = try XCTUnwrap(source.range(of: "private func updateSettings"))
        let calibrationBody = source[calibrationStart.lowerBound..<nextFunction.lowerBound]

        XCTAssertTrue(calibrationBody.contains("CalibrationStartController.requiresLifecycleCleanupBeforeStarting(from: state)"))
        XCTAssertTrue(calibrationBody.contains("stopMonitoring(source: .userRequested)"))

        let cleanupRange = try XCTUnwrap(calibrationBody.range(of: "stopMonitoring(source: .userRequested)"))
        let captureRange = try XCTUnwrap(calibrationBody.range(of: "monitor.captureCalibrationSampleSet()"))
        XCTAssertLessThan(cleanupRange.lowerBound, captureRange.lowerBound)
    }

    func testAppSourceCleansMonitoringLifecycleBeforeResettingCalibration() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/GlanceHoldApp.swift"), encoding: .utf8)
        let resetStart = try XCTUnwrap(source.range(of: "private func resetCalibrationWithConfirmation"))
        let nextFunction = try XCTUnwrap(source.range(of: "private func handleCalibrationResult"))
        let resetBody = source[resetStart.lowerBound..<nextFunction.lowerBound]

        XCTAssertTrue(resetBody.contains("CalibrationStartController.requiresLifecycleCleanupBeforeStarting(from: state)"))
        XCTAssertTrue(resetBody.contains("stopMonitoring(source: .userRequested)"))

        let confirmationRange = try XCTUnwrap(resetBody.range(of: "guard alert.runModal() == .alertSecondButtonReturn"))
        let cleanupRange = try XCTUnwrap(resetBody.range(of: "stopMonitoring(source: .userRequested)"))
        let resetRange = try XCTUnwrap(resetBody.range(of: "monitor.resetCalibration()"))
        XCTAssertLessThan(confirmationRange.lowerBound, cleanupRange.lowerBound)
        XCTAssertLessThan(cleanupRange.lowerBound, resetRange.lowerBound)
    }

    func testAppSourceUsesStatusStreamLivenessInsteadOfFixedSnapshotFallbackPolling() throws {
        let source = try String(contentsOf: projectFileURL("GlanceHold/GlanceHoldApp.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("playbackFallbackRefreshTask"))
        XCTAssertFalse(source.contains("playbackFallbackRefreshIntervalNanoseconds"))
        XCTAssertTrue(source.contains("playbackStatusStreamReconnectIntervalNanoseconds"))

        let startRange = try XCTUnwrap(source.range(of: "private func startPlaybackStatusUpdates()"))
        let toggleRange = try XCTUnwrap(source.range(of: "private func startMonitoringToggleRequestHandling()"))
        let statusUpdateSource = String(source[startRange.lowerBound..<toggleRange.lowerBound])

        XCTAssertTrue(statusUpdateSource.contains("await coordinator.observePlayerStatusUpdates()"))
        XCTAssertTrue(statusUpdateSource.contains("playbackStatusStreamReconnectIntervalNanoseconds"))
        XCTAssertFalse(statusUpdateSource.contains("refreshPlayerState()"))
        XCTAssertFalse(statusUpdateSource.contains("10_000_000_000"))
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

    private func projectFileURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}

private final class FakeDiagnosticSettingsStore: DiagnosticSettingsStoring {
    private var settings: DiagnosticSettings
    private(set) var savedSettings: [DiagnosticSettings] = []
    private(set) var events: [String] = []

    init(settings: DiagnosticSettings) {
        self.settings = settings
    }

    func load() -> DiagnosticSettings {
        events.append("load")
        return settings
    }

    func save(_ settings: DiagnosticSettings) throws {
        self.settings = settings
        savedSettings.append(settings)
        events.append("save:\(settings.isEnabled)")
    }

    func noteRestartObserved() {
        events.append("restartObserved:\(settings.isEnabled)")
    }
}

private final class FakeAppRestartRequester: AppRestartRequesting {
    private(set) var requestCount = 0
    private(set) var events: [String] = []
    var shouldFail = false
    weak var store: FakeDiagnosticSettingsStore?

    func requestRestart(onFailure: @escaping () -> Void) {
        requestCount += 1
        store?.noteRestartObserved()
        events.append("restart")
        if shouldFail {
            onFailure()
        }
    }
}

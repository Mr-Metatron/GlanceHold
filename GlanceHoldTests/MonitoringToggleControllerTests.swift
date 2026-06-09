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
    weak var store: FakeDiagnosticSettingsStore?

    func requestRestart() {
        requestCount += 1
        store?.noteRestartObserved()
        events.append("restart")
    }
}

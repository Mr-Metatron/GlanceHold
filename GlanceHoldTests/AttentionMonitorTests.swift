import XCTest
@testable import GlanceHold

final class AttentionMonitorTests: XCTestCase {
    func testStartMonitoringRequestsPermissionOnlyFromExplicitCallAndNeedsCalibrationDoesNotStartCapture() async {
        let permission = MonitorPermissionProvider(status: .undetermined, requestResult: true)
        let capture = FakeCameraFrameCapture()
        let monitor = AttentionMonitor(permissionProvider: permission, settingsStore: MonitorSettingsStore(), capture: capture, analyzer: FakeVisionAnalyzer())

        XCTAssertEqual(permission.requestCount, 0)
        XCTAssertEqual(capture.startCount, 0)

        await monitor.startMonitoring()

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(monitor.state, .needsCalibration)
    }

    func testDeniedAndRestrictedPermissionNeverStartCapture() async {
        for status in [CameraPermissionStatus.denied, .restricted] {
            let permission = MonitorPermissionProvider(status: status, requestResult: false)
            let capture = FakeCameraFrameCapture()
            let monitor = AttentionMonitor(permissionProvider: permission, settingsStore: MonitorSettingsStore(), capture: capture, analyzer: FakeVisionAnalyzer())

            await monitor.startMonitoring()

            XCTAssertEqual(permission.requestCount, 0)
            XCTAssertEqual(capture.startCount, 0)
            XCTAssertEqual(monitor.state, .cameraPermissionDenied)
        }
    }

    func testCameraUnavailableEmitsSafeStateWithoutPlaybackSideEffects() async {
        let capture = FakeCameraFrameCapture(startError: CameraFrameCaptureError.unavailable)
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: capture,
            analyzer: FakeVisionAnalyzer()
        )

        await monitor.startMonitoring()

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(monitor.state, .cameraUnavailable)
    }

    func testDisablingMonitoringStopsCaptureExactlyOnce() async {
        let capture = FakeCameraFrameCapture()
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: capture,
            analyzer: FakeVisionAnalyzer()
        )

        await monitor.startMonitoring()
        monitor.stopMonitoring()
        monitor.stopMonitoring()

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(monitor.state, .off)
    }

    func testCalibrationSavesHighAndMarginalScalarSnapshots() async throws {
        let store = MonitorSettingsStore()
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        let high = await monitor.startCalibration(samples: samples(spread: 0.4))

        XCTAssertEqual(monitor.state, .ready)
        guard case .accepted(let highSnapshot) = high else {
            return XCTFail("Expected accepted high calibration")
        }
        XCTAssertEqual(highSnapshot.quality, .high)
        XCTAssertEqual(store.load().calibration?.quality, .high)

        let marginalStore = MonitorSettingsStore()
        let marginalMonitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: marginalStore,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )
        let marginal = await marginalMonitor.startCalibration(samples: samples(spread: 2.0))

        guard case .accepted(let marginalSnapshot) = marginal else {
            return XCTFail("Expected accepted marginal calibration")
        }
        XCTAssertEqual(marginalSnapshot.quality, .marginal)
        XCTAssertEqual(marginalStore.load().calibration?.quality, .marginal)
    }

    func testCalibrationFailurePreservesPreviousCalibration() async {
        let previous = snapshot(.high)
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(previous))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        let result = await monitor.startCalibration(samples: [])

        XCTAssertEqual(result, .failed(previous: previous))
        XCTAssertEqual(store.load().calibration, previous)
        XCTAssertEqual(monitor.state, .calibrationFailed(previousKept: true))
    }

    func testCalibrationSaveFailureLeavesMonitorUnavailable() async {
        let store = MonitorSettingsStore(saveError: MonitorStoreError.saveFailed)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        let result = await monitor.startCalibration(samples: samples(spread: 0.4))

        guard case .accepted = result else {
            return XCTFail("Expected valid samples to be accepted before save failure")
        }
        XCTAssertNil(store.load().calibration)
        XCTAssertEqual(monitor.state, .unavailable)
    }

    func testRawObservationsFlowThroughDebounceToVisibleStates() async {
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        await monitor.startMonitoring()

        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0))), .facing)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.1))), .facing)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.9))), .lookingAway)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.0))), .recovering)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.6))), .facing)
        XCTAssertEqual(monitor.applySample(.noFace(time: 2.0)), .facing)
        XCTAssertEqual(monitor.applySample(.noFace(time: 2.8)), .noFaceDetected)
    }

    func testUncalibratedAndAmbiguousObservationsAreSafeUnavailableStates() {
        let uncalibrated = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(uncalibrated.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0))), .needsCalibration)

        let calibrated = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(calibrated.applySample(.ambiguous(time: 0.0)), .unavailable)
    }

    func testSettingsUpdatesSaveImmediatelyAndSurviveReload() throws {
        let store = MonitorSettingsStore()
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        var settings = monitor.settings
        settings.mode = .pauseResume
        settings = settings.withSensitivity(.strict)
        settings.speedControlAwayDelay = 0.5
        settings.pauseResumeAwayDelay = 1.6
        settings.recoveryDelay = 0.7

        try monitor.updateSettings(settings)

        XCTAssertEqual(store.load(), settings)
        let reloaded = AttentionMonitor(permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true), settingsStore: store, capture: FakeCameraFrameCapture(), analyzer: FakeVisionAnalyzer()).settings
        XCTAssertEqual(reloaded, settings)
        XCTAssertEqual(reloaded.timing(for: .speedControl), AttentionTiming(awayDelay: 0.5, recoveryDelay: 0.7))
        XCTAssertEqual(reloaded.timing(for: .pauseResume), AttentionTiming(awayDelay: 1.6, recoveryDelay: 0.7))
    }

    private func samples(spread: Double) -> [PoseSample] {
        [
            makePose(yaw: 0.0, pitch: 0.0, time: 0.0),
            makePose(yaw: spread, pitch: spread, time: 0.1),
            makePose(yaw: spread / 2.0, pitch: spread / 2.0, time: 0.2)
        ]
    }
}

private final class MonitorPermissionProvider: CameraPermissionProviding {
    private let status: CameraPermissionStatus
    private let requestResult: Bool
    private(set) var requestCount = 0

    init(status: CameraPermissionStatus, requestResult: Bool) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> CameraPermissionStatus {
        status
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        return requestResult
    }
}

private final class MonitorSettingsStore: AttentionSettingsStoring {
    private var storedSettings: AttentionSettings
    private let saveError: Error?

    init(settings: AttentionSettings = .defaults, saveError: Error? = nil) {
        self.storedSettings = settings
        self.saveError = saveError
    }

    func load() -> AttentionSettings {
        storedSettings
    }

    func save(_ settings: AttentionSettings) throws {
        if let saveError {
            throw saveError
        }
        storedSettings = settings
    }

    func reset() throws {
        storedSettings = .defaults
    }
}

private enum MonitorStoreError: Error {
    case saveFailed
}

private final class FakeCameraFrameCapture: CameraFrameCapturing {
    var frameHandler: ((CapturedCameraFrame) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let startError: Error?
    private var isRunning = false

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start() async throws {
        startCount += 1
        if let startError {
            throw startError
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }
        stopCount += 1
        isRunning = false
    }
}

private struct FakeVisionAnalyzer: VisionAttentionAnalyzing {
    var observation: VisionAttentionObservation = .ambiguous(time: 0.0)

    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation {
        observation
    }
}

private func snapshot(_ quality: CalibrationQuality) -> CalibrationSnapshot {
    CalibrationSnapshot(
        neutralPose: makePose(yaw: 0.0, pitch: 0.0),
        quality: quality,
        createdAt: Date(timeIntervalSince1970: 1.0)
    )
}

private func makePose(yaw: Double, pitch: Double, roll: Double = 0.0, time: TimeInterval = 0.0) -> PoseSample {
    PoseSample(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll, time: time)
}

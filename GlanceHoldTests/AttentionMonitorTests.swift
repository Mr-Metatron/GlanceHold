import CoreMedia
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
        var sessionChanges: [DiagnosticSession?] = []
        monitor.diagnosticSessionDidChange = { sessionChanges.append($0) }

        await monitor.startMonitoring()

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertNil(capture.frameHandler)
        XCTAssertEqual(monitor.state, .cameraUnavailable)
        XCTAssertNil(monitor.currentDiagnosticSession)
        XCTAssertEqual(sessionChanges.count, 1)
        XCTAssertNil(sessionChanges[0])
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
        XCTAssertNil(capture.frameHandler)
        XCTAssertEqual(monitor.state, .off)
    }

    func testStartMonitoringDoesNotReenterWhileWaitingForFirstSample() async {
        let capture = FakeCameraFrameCapture()
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: capture,
            analyzer: FakeVisionAnalyzer()
        )

        await monitor.startMonitoring()
        await monitor.startMonitoring()

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(monitor.state, .monitoringPendingFirstSample)
    }

    func testStartMonitoringDoesNotReenterWhileCaptureStartIsInFlight() async {
        let capture = FakeCameraFrameCapture(suspendedStartCount: 1)
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: capture,
            analyzer: FakeVisionAnalyzer()
        )

        let startTask = Task {
            await monitor.startMonitoring()
        }

        await capture.waitForStartCall()
        await monitor.startMonitoring()

        XCTAssertEqual(capture.startCount, 1)

        capture.completeSuspendedStart()
        await startTask.value

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(monitor.state, .monitoringPendingFirstSample)
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

    func testCameraBackedFirstTimeCalibrationFailureShowsExplicitFailure() async {
        let capture = FakeCameraFrameCapture()
        let analyzer = SequencedVisionAnalyzer(observations: [
            .ambiguous(time: 0.0),
            .noFace(time: 0.1),
            .ambiguous(time: 0.2)
        ])
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(),
            capture: capture,
            analyzer: analyzer
        )

        let resultTask = Task {
            await monitor.captureCalibrationSampleSet(targetSampleCount: 3, maximumFrameCount: 3)
        }

        await capture.waitForFrameHandler()
        capture.emitFrame(time: 0.0)
        capture.emitFrame(time: 0.1)
        capture.emitFrame(time: 0.2)

        let result = await resultTask.value

        XCTAssertEqual(result, .failed(previous: nil))
        XCTAssertEqual(monitor.state, .calibrationFailed(previousKept: false))
        XCTAssertEqual(
            MonitoringStatus(monitorState: monitor.state).visibleTitle,
            GlanceHoldStrings.text(.monitoringCalibrationFailedTitle)
        )
        XCTAssertEqual(
            MonitoringStatus(monitorState: monitor.state).detailText,
            GlanceHoldStrings.text(.monitoringCalibrationFailedRetryDetail)
        )
    }

    func testCameraBackedCalibrationAcceptsStableWindowAfterNoisyStartup() async {
        let capture = FakeCameraFrameCapture()
        let store = MonitorSettingsStore()
        let analyzer = SequencedVisionAnalyzer(observations: [
            .pose(makePose(yaw: -10.0, pitch: 5.0, roll: 1.0, time: 0.0)),
            .pose(makePose(yaw: 8.0, pitch: -4.0, roll: -1.0, time: 0.1)),
            .pose(makePose(yaw: 0.2, pitch: -0.1, roll: 0.1, time: 0.2)),
            .pose(makePose(yaw: 0.4, pitch: 0.0, roll: -0.1, time: 0.5)),
            .pose(makePose(yaw: 0.3, pitch: 0.1, roll: 0.0, time: 0.8)),
            .pose(makePose(yaw: 0.1, pitch: 0.0, roll: 0.1, time: 1.1)),
            .pose(makePose(yaw: 0.2, pitch: 0.1, roll: 0.0, time: 1.4))
        ])
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: capture,
            analyzer: analyzer
        )

        let resultTask = Task {
            await monitor.captureCalibrationSampleSet(
                targetSampleCount: 5,
                maximumFrameCount: 7
            )
        }

        await capture.waitForFrameHandler()
        for time in [0.0, 0.1, 0.2, 0.5, 0.8, 1.1, 1.4] {
            capture.emitFrame(time: time)
        }

        let result = await resultTask.value

        guard case let .accepted(snapshot) = result else {
            return XCTFail("Expected camera-backed calibration to accept the stable window")
        }

        XCTAssertEqual(snapshot.quality, .high)
        XCTAssertEqual(store.load().calibration, snapshot)
        XCTAssertEqual(monitor.state, .ready)
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testCameraBackedCalibrationFailsWhenNoStableWindowExists() async {
        let capture = FakeCameraFrameCapture()
        let analyzer = SequencedVisionAnalyzer(observations: [
            .pose(makePose(yaw: -10.0, pitch: 4.0, time: 0.0)),
            .pose(makePose(yaw: -3.0, pitch: -4.0, time: 0.1)),
            .pose(makePose(yaw: 4.0, pitch: 4.0, time: 0.2)),
            .pose(makePose(yaw: 11.0, pitch: -4.0, time: 0.3)),
            .pose(makePose(yaw: 18.0, pitch: 4.0, time: 0.4))
        ])
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(),
            capture: capture,
            analyzer: analyzer
        )

        let resultTask = Task {
            await monitor.captureCalibrationSampleSet(
                targetSampleCount: 5,
                maximumFrameCount: 5
            )
        }

        await capture.waitForFrameHandler()
        for time in stride(from: 0.0, through: 0.4, by: 0.1) {
            capture.emitFrame(time: time)
        }

        let result = await resultTask.value

        XCTAssertEqual(result, .failed(previous: nil))
        XCTAssertEqual(monitor.state, .calibrationFailed(previousKept: false))
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testStaleCalibrationCleanupDoesNotStopNewMonitoringSession() async throws {
        let capture = FakeCameraFrameCapture()
        let calibration = snapshot(.high)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(calibration)),
            capture: capture,
            analyzer: FakeVisionAnalyzer()
        )

        let calibrationTask = Task {
            await monitor.captureCalibrationSampleSet(
                targetSampleCount: 5,
                maximumFrameCount: 20,
                minimumCaptureDuration: 10.0,
                maximumCaptureDuration: 0.05
            )
        }

        await capture.waitUntilRunning()
        monitor.stopMonitoring()

        await monitor.startMonitoring()
        await capture.waitForFrameHandler()

        XCTAssertEqual(capture.startCount, 2)
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(monitor.state, .monitoringPendingFirstSample)
        XCTAssertNotNil(capture.frameHandler)

        _ = await calibrationTask.value
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertNotNil(capture.frameHandler)
        XCTAssertEqual(monitor.state, .monitoringPendingFirstSample)
    }

    func testCameraBackedCalibrationKeepsSamplingUntilMinimumDurationOrFrameBound() async {
        let capture = FakeCameraFrameCapture()
        let analyzer = SequencedVisionAnalyzer(observations: [
            .pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0)),
            .pose(makePose(yaw: 0.1, pitch: 0.0, time: 0.25)),
            .pose(makePose(yaw: 0.2, pitch: 0.0, time: 0.5)),
            .pose(makePose(yaw: 0.1, pitch: 0.1, time: 0.75)),
            .pose(makePose(yaw: 0.2, pitch: 0.1, time: 1.0))
        ])
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(),
            capture: capture,
            analyzer: analyzer
        )

        let resultTask = Task {
            await monitor.captureCalibrationSampleSet(
                targetSampleCount: 3,
                maximumFrameCount: 5,
                minimumCaptureDuration: 10.0,
                maximumCaptureDuration: 20.0
            )
        }

        await capture.waitForFrameHandler()
        for time in stride(from: 0.0, through: 0.4, by: 0.1) {
            capture.emitFrame(time: time)
        }

        guard case .accepted = await resultTask.value else {
            return XCTFail("Expected stable samples to calibrate")
        }

        XCTAssertEqual(analyzer.analyzeCount, 5)
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(monitor.state, .ready)
    }

    func testMarginalReplacementDecisionPersistsChosenCalibration() async throws {
        let existing = snapshot(.high)
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(existing))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        let result = await monitor.startCalibration(samples: samples(spread: 2.0))

        guard case .needsReplacementConfirmation(let candidate, let current) = result else {
            return XCTFail("Expected marginal replacement confirmation")
        }
        XCTAssertEqual(current, existing)
        XCTAssertEqual(store.load().calibration, existing)

        try monitor.applyCalibrationReplacement(candidate: candidate, existing: current, decision: .useNew)

        XCTAssertEqual(store.load().calibration, candidate)
        XCTAssertEqual(monitor.state, .ready)
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

    func testTransientAmbiguousAndFailedObservationsPreserveFacingState() {
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0))), .facing)
        XCTAssertEqual(monitor.applySample(.ambiguous(time: 0.2)), .facing)
        XCTAssertEqual(monitor.applySample(.failed(time: 0.3)), .facing)
    }

    func testTransientAmbiguousAndFailedObservationsPreserveAwayAndNoFaceStates() {
        let awayMonitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(awayMonitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.0))), .facing)
        XCTAssertEqual(awayMonitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.8))), .lookingAway)
        XCTAssertEqual(awayMonitor.applySample(.ambiguous(time: 1.0)), .lookingAway)
        XCTAssertEqual(awayMonitor.applySample(.failed(time: 1.1)), .lookingAway)

        let noFaceMonitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(noFaceMonitor.applySample(.noFace(time: 0.0)), .facing)
        XCTAssertEqual(noFaceMonitor.applySample(.noFace(time: 0.8)), .noFaceDetected)
        XCTAssertEqual(noFaceMonitor.applySample(.ambiguous(time: 1.0)), .noFaceDetected)
        XCTAssertEqual(noFaceMonitor.applySample(.failed(time: 1.1)), .noFaceDetected)
    }

    func testTransientAmbiguousAndFailedObservationsPreserveRecoveringStateUntilDelayCompletes() {
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.0))), .facing)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.8))), .lookingAway)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.9))), .recovering)
        XCTAssertEqual(monitor.applySample(.ambiguous(time: 1.1)), .recovering)
        XCTAssertEqual(monitor.applySample(.failed(time: 1.2)), .recovering)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.5))), .recovering)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.9))), .facing)
    }

    func testSustainedUnavailableRequiresRecoveryBeforeFacingStateReturns() {
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0))), .facing)
        XCTAssertEqual(monitor.applySample(.ambiguous(time: 0.1)), .facing)
        XCTAssertEqual(monitor.applySample(.failed(time: 0.7)), .unavailable)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.8))), .recovering)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.3))), .recovering)
        XCTAssertEqual(monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 1.4))), .facing)
    }

    func testUncalibratedObservationRemainsNeedsCalibrationAndSustainedAmbiguousBecomesUnavailable() {
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

        XCTAssertEqual(calibrated.applySample(.ambiguous(time: 0.0)), .facing)
        XCTAssertEqual(calibrated.applySample(.ambiguous(time: 0.6)), .unavailable)
    }

    func testMonitorNotifiesWhenSamplesChangeVisibleState() {
        let store = MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high)))
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )
        var notifiedStates: [AttentionMonitorState] = []
        monitor.stateDidChange = { state, _ in
            notifiedStates.append(state)
        }

        _ = monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.1)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.9)))

        XCTAssertEqual(notifiedStates, [.facing, .facing, .lookingAway])
    }

    func testDefaultModeDiagnosticsStayQuietAndRecordFinalSummary() async {
        let recorder = MonitorDiagnosticRecorder(mode: .default)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer(),
            diagnosticRecorder: recorder,
            diagnosticMode: .default
        )

        await monitor.startMonitoring()
        for index in 0..<30 {
            _ = monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: Double(index) * 0.1)))
        }
        monitor.stopMonitoring()

        let eventNames = recorder.events.map(\.name)
        XCTAssertFalse(eventNames.contains(.frameReceived))
        XCTAssertFalse(eventNames.contains(.analysisCompleted))
        XCTAssertFalse(eventNames.contains(.repeatedStableState))
        XCTAssertFalse(eventNames.contains(.attentionTransition))
        XCTAssertFalse(recorder.events.contains { $0.name == .runtimeSummary && fieldValue(.summaryKind, in: $0) == "periodic" })
        XCTAssertTrue(recorder.events.contains { $0.name == .runtimeSummary && fieldValue(.summaryKind, in: $0) == "final" })
    }

    func testCameraBackedMonitoringSamplesFake30fpsAtFiveHzAndCountsSkippedSamples() async {
        let recorder = MonitorDiagnosticRecorder(mode: .diagnostic)
        let capture = FakeCameraFrameCapture()
        let analyzer = TimestampEchoVisionAnalyzer()
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: capture,
            analyzer: analyzer,
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            runtimeSummaryInterval: 1.0
        )

        await monitor.startMonitoring()
        await capture.waitForFrameHandler()

        let frameCount = 60
        let framesPerSecond = 30.0
        for index in 0..<frameCount {
            capture.emitFrame(time: Double(index) / framesPerSecond)
        }

        await drainMainActor()
        monitor.stopMonitoring()

        let allowedAnalyses = Int(floor(2.0 * 5.0)) + 2
        XCTAssertLessThanOrEqual(
            analyzer.analyzeCount,
            allowedAnalyses,
            "fake 30fps monitoring should stay at 5 Hz plus startup/timing tolerance"
        )

        guard let finalSummary = recorder.events.last(where: { $0.name == .runtimeSummary && fieldValue(.summaryKind, in: $0) == "final" }) else {
            return XCTFail("Expected a final runtime summary")
        }

        XCTAssertEqual(fieldValue(.framesReceived, in: finalSummary), "\(frameCount)")
        XCTAssertEqual(fieldValue(.framesAnalyzed, in: finalSummary), "\(analyzer.analyzeCount)")
        XCTAssertEqual(fieldValue(.skippedSamples, in: finalSummary), "\(frameCount - analyzer.analyzeCount)")
        XCTAssertGreaterThan(frameCount - analyzer.analyzeCount, 0)

        guard let analyzerRate = fieldValue(.analyzerRateHz, in: finalSummary).flatMap(Double.init)
        else {
            return XCTFail("Expected a final runtime summary with analyzerRateHz")
        }
        XCTAssertLessThanOrEqual(analyzerRate, 5.5, "analyzerRateHz should stay within 5 Hz plus fake-timestamp tolerance")
    }

    func testDiagnosticModeRecordsAttentionBreadcrumbsAndPeriodicSummary() async {
        let recorder = MonitorDiagnosticRecorder(mode: .diagnostic)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer(),
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic,
            runtimeSummaryInterval: 5.0
        )

        await monitor.startMonitoring()
        _ = monitor.applySample(.pose(makePose(yaw: 0.0, pitch: 0.0, time: 0.0)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.1)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 1.1)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 6.2)))

        let transitions = recorder.events.filter { $0.name == .attentionTransition }
        XCTAssertFalse(transitions.isEmpty)
        XCTAssertTrue(transitions.contains { event in
            fieldValue(.rawSignal, in: event) == "away"
                && fieldValue(.previousState, in: event) == "facing"
                && fieldValue(.nextState, in: event) == "lookingAway"
                && fieldValue(.transitionReason, in: event) == "thresholdReached"
        })
        XCTAssertTrue(recorder.events.contains { $0.name == .runtimeSummary && fieldValue(.summaryKind, in: $0) == "periodic" })
    }

    func testMonitoringDiagnosticsShareSessionAndIncreasingSequence() async {
        let recorder = MonitorDiagnosticRecorder(mode: .diagnostic)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer(),
            diagnosticRecorder: recorder,
            diagnosticMode: .diagnostic
        )

        await monitor.startMonitoring()
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 0.0)))
        _ = monitor.applySample(.pose(makePose(yaw: 30.0, pitch: 0.0, time: 1.0)))
        monitor.stopMonitoring()

        let monitoringEvents = recorder.events.filter { $0.sessionKind == .monitoring }
        let sessionIDs = Set(monitoringEvents.map(\.sessionID))
        XCTAssertEqual(sessionIDs.count, 1)
        XCTAssertEqual(monitoringEvents.map(\.sequence), monitoringEvents.map(\.sequence).sorted())
        XCTAssertEqual(Set(monitoringEvents.map(\.category)), [.monitoring, .attention, .runtimeSummary])
    }

    func testMonitoringDiagnosticSessionLifecycleNotifiesPlaybackBridge() async {
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(settings: .defaults.withCalibration(snapshot(.high))),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )
        var sessionChanges: [DiagnosticSession?] = []
        monitor.diagnosticSessionDidChange = { session in
            sessionChanges.append(session)
        }

        await monitor.startMonitoring()
        monitor.stopMonitoring()

        XCTAssertEqual(sessionChanges.count, 2)
        XCTAssertEqual(sessionChanges.first??.kind, .monitoring)
        XCTAssertNil(sessionChanges.last!)
    }

    func testCalibrationDiagnosticsAreScalarAndUseCalibrationSession() async {
        let recorder = MonitorDiagnosticRecorder(mode: .default)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: MonitorSettingsStore(),
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer(),
            diagnosticRecorder: recorder
        )

        _ = await monitor.startCalibration(samples: samples(spread: 0.4))

        guard let calibrationEnded = recorder.events.first(where: { $0.name == .calibrationEnded }) else {
            return XCTFail("Expected calibrationEnded diagnostic event")
        }
        XCTAssertEqual(calibrationEnded.category, .calibration)
        XCTAssertEqual(calibrationEnded.sessionKind, .calibration)
        XCTAssertEqual(calibrationEnded.fields.map(\.name), [
            .calibrationFrameCount,
            .calibrationPoseCount,
            .calibrationNoFaceCount,
            .calibrationAmbiguousCount,
            .calibrationFailedCount,
            .inputSampleCount,
            .selectedWindowSampleCount,
            .selectedWindowDurationSeconds,
            .selectedWindowSpreadDegrees,
            .selectedWindowQuality,
            .failureReason,
            .captureEndReason
        ])
        let fieldNames = calibrationEnded.fields.map { $0.name.rawValue }
        XCTAssertFalse(fieldNames.contains("sampleBuffer"))
        XCTAssertFalse(fieldNames.contains("image"))
        XCTAssertFalse(fieldNames.contains("faceBox"))
        XCTAssertFalse(fieldNames.contains("rawPoseStream"))
        XCTAssertEqual(fieldValue(.selectedWindowSampleCount, in: calibrationEnded), "5")
        XCTAssertEqual(fieldValue(.selectedWindowDurationSeconds, in: calibrationEnded), "1.000")
    }

    func testResetCalibrationClearsOnlyCalibrationAndPreservesTuning() throws {
        let calibration = snapshot(.high)
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .strict,
            headTurnThresholdDegrees: 14.0,
            speedControlAwayDelay: 1.5,
            pauseResumeAwayDelay: 2.0,
            recoveryDelay: 0.5,
            calibration: calibration
        )
        let store = MonitorSettingsStore(settings: settings)
        let monitor = AttentionMonitor(
            permissionProvider: MonitorPermissionProvider(status: .granted, requestResult: true),
            settingsStore: store,
            capture: FakeCameraFrameCapture(),
            analyzer: FakeVisionAnalyzer()
        )

        try monitor.resetCalibration()

        let expected = settings.withCalibration(nil)
        XCTAssertEqual(monitor.settings, expected)
        XCTAssertEqual(store.load(), expected)
        XCTAssertNil(monitor.settings.calibration)
        XCTAssertEqual(monitor.settings.mode, settings.mode)
        XCTAssertEqual(monitor.settings.sensitivity, settings.sensitivity)
        XCTAssertEqual(monitor.settings.headTurnThresholdDegrees, settings.headTurnThresholdDegrees)
        XCTAssertEqual(monitor.settings.speedControlAwayDelay, settings.speedControlAwayDelay)
        XCTAssertEqual(monitor.settings.pauseResumeAwayDelay, settings.pauseResumeAwayDelay)
        XCTAssertEqual(monitor.settings.recoveryDelay, settings.recoveryDelay)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.resetCount, 0)
        XCTAssertEqual(monitor.state, .needsCalibration)
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
            makePose(yaw: spread, pitch: spread, time: 0.25),
            makePose(yaw: spread / 2.0, pitch: spread / 2.0, time: 0.5),
            makePose(yaw: spread / 4.0, pitch: spread / 4.0, time: 0.75),
            makePose(yaw: spread * 0.75, pitch: spread * 0.75, time: 1.0)
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
    private(set) var saveCount = 0
    private(set) var resetCount = 0

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
        saveCount += 1
        storedSettings = settings
    }

    func reset() throws {
        resetCount += 1
        storedSettings = .defaults
    }
}

private enum MonitorStoreError: Error {
    case saveFailed
}

private final class FakeCameraFrameCapture: CameraFrameCapturing {
    var frameHandler: ((CapturedCameraFrame) -> Void)? {
        didSet {
            if frameHandler != nil {
                frameHandlerContinuation?.resume()
                frameHandlerContinuation = nil
            }
        }
    }
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let startError: Error?
    private var suspendedStartCount: Int
    private var isRunning = false
    private var startCallContinuation: CheckedContinuation<Void, Never>?
    private var suspendedStartContinuation: CheckedContinuation<Void, Error>?
    private var runningContinuation: CheckedContinuation<Void, Never>?
    private var frameHandlerContinuation: CheckedContinuation<Void, Never>?

    init(startError: Error? = nil, suspendedStartCount: Int = 0) {
        self.startError = startError
        self.suspendedStartCount = suspendedStartCount
    }

    func start() async throws {
        startCount += 1
        startCallContinuation?.resume()
        startCallContinuation = nil

        if suspendedStartCount > 0 {
            suspendedStartCount -= 1
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                suspendedStartContinuation = continuation
            }
        }

        if let startError {
            throw startError
        }
        isRunning = true
        runningContinuation?.resume()
        runningContinuation = nil
    }

    func stop() {
        guard isRunning else {
            return
        }
        stopCount += 1
        isRunning = false
    }

    func waitForStartCall() async {
        if startCount > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            if startCount > 0 {
                continuation.resume()
            } else {
                startCallContinuation = continuation
            }
        }
    }

    func completeSuspendedStart(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let suspendedStartContinuation else {
            XCTFail("Expected a suspended start", file: file, line: line)
            return
        }

        self.suspendedStartContinuation = nil
        suspendedStartContinuation.resume(returning: ())
    }

    func waitUntilRunning(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        if isRunning {
            return
        }

        await withCheckedContinuation { continuation in
            if isRunning {
                continuation.resume()
            } else {
                runningContinuation = continuation
            }
        }
        XCTAssertTrue(isRunning, file: file, line: line)
    }

    func waitForFrameHandler(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        if frameHandler != nil {
            return
        }

        await withCheckedContinuation { continuation in
            if frameHandler != nil {
                continuation.resume()
            } else {
                frameHandlerContinuation = continuation
            }
        }
        XCTAssertNotNil(frameHandler, file: file, line: line)
    }

    func emitFrame(time: TimeInterval) {
        frameHandler?(CapturedCameraFrame(sampleBuffer: makeSampleBuffer(), time: time))
    }
}

private struct FakeVisionAnalyzer: VisionAttentionAnalyzing {
    var observation: VisionAttentionObservation = .ambiguous(time: 0.0)

    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation {
        observation
    }
}

private final class TimestampEchoVisionAnalyzer: VisionAttentionAnalyzing {
    private(set) var analyzeCount = 0

    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation {
        analyzeCount += 1
        return .pose(makePose(yaw: 0.0, pitch: 0.0, time: frame.time))
    }
}

private final class SequencedVisionAnalyzer: VisionAttentionAnalyzing {
    private var observations: [VisionAttentionObservation]
    private(set) var analyzeCount = 0

    init(observations: [VisionAttentionObservation]) {
        self.observations = observations
    }

    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation {
        analyzeCount += 1
        return observations.isEmpty ? .ambiguous(time: frame.time) : observations.removeFirst()
    }
}

private final class MonitorDiagnosticRecorder: DiagnosticRecording {
    let mode: DiagnosticMode
    private(set) var events: [DiagnosticEvent] = []

    init(mode: DiagnosticMode) {
        self.mode = mode
    }

    @discardableResult
    func record(_ request: DiagnosticEventRequest, in session: DiagnosticSession) -> DiagnosticEvent? {
        guard DiagnosticEventPolicy.shouldRecord(request, mode: mode) else {
            return nil
        }

        let event = DiagnosticEvent(
            category: request.category,
            name: request.name,
            sessionID: session.id,
            sessionKind: session.kind,
            sequence: session.nextSequence(),
            fields: request.fields
        )
        events.append(event)
        return event
    }
}

private func fieldValue(_ name: DiagnosticFieldName, in event: DiagnosticEvent) -> String? {
    event.fields.first { $0.name == name }?.value.logValue
}

private func drainMainActor() async {
    await MainActor.run {}
    await Task.yield()
    await MainActor.run {}
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

private func makeSampleBuffer() -> CMSampleBuffer {
    var sampleBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: nil,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: nil,
        sampleCount: 0,
        sampleTimingEntryCount: 0,
        sampleTimingArray: nil,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    precondition(status == noErr)
    return sampleBuffer!
}

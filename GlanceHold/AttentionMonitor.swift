import Foundation

enum AttentionMonitorState: Equatable {
    case off
    case needsCalibration
    case calibrating
    case ready
    case facing
    case lookingAway
    case noFaceDetected
    case recovering
    case cameraPermissionDenied
    case cameraUnavailable
    case calibrationFailed(previousKept: Bool)
    case unavailable
}

final class AttentionMonitor {
    private let permissionProvider: CameraPermissionProviding
    private let settingsStore: AttentionSettingsStoring
    private let capture: CameraFrameCapturing
    private let analyzer: VisionAttentionAnalyzing
    private var stateMachine: AttentionStateMachine
    private var isCaptureRunning = false

    private(set) var state: AttentionMonitorState
    private(set) var settings: AttentionSettings

    init(
        permissionProvider: CameraPermissionProviding,
        settingsStore: AttentionSettingsStoring,
        capture: CameraFrameCapturing,
        analyzer: VisionAttentionAnalyzing
    ) {
        self.permissionProvider = permissionProvider
        self.settingsStore = settingsStore
        self.capture = capture
        self.analyzer = analyzer

        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.stateMachine = AttentionStateMachine(timing: loadedSettings.timing(for: loadedSettings.mode))
        self.state = loadedSettings.calibration == nil ? .needsCalibration : .ready
    }

    func startMonitoring() async {
        guard await resolvePermission() else {
            state = .cameraPermissionDenied
            return
        }

        guard settings.calibration != nil else {
            state = .needsCalibration
            return
        }

        capture.frameHandler = { [weak self] frame in
            guard let self else {
                return
            }

            _ = self.applySample(self.analyzer.analyze(frame))
        }

        do {
            try await capture.start()
            isCaptureRunning = true
            state = .ready
        } catch CameraFrameCaptureError.unavailable {
            state = .cameraUnavailable
        } catch {
            state = .unavailable
        }
    }

    func stopMonitoring() {
        guard isCaptureRunning else {
            state = .off
            return
        }

        capture.stop()
        isCaptureRunning = false
        state = .off
    }

    func startCalibration() {
        state = .calibrating
    }

    func startCalibration(samples: [PoseSample]) async -> CalibrationResult {
        state = .calibrating

        let result = CalibrationModel.evaluate(samples: samples, existing: settings.calibration)
        switch result {
        case .accepted(let snapshot):
            if saveCalibration(snapshot) {
                state = .ready
            }
        case .needsReplacementConfirmation:
            state = .ready
        case .failed(let previous):
            state = previous == nil ? .needsCalibration : .calibrationFailed(previousKept: true)
        }

        return result
    }

    @discardableResult
    func applySample(_ observation: VisionAttentionObservation) -> AttentionMonitorState {
        guard settings.calibration != nil else {
            state = .needsCalibration
            return state
        }

        let signal: RawAttentionSignal
        let time: TimeInterval

        switch observation {
        case .pose(let sample):
            signal = CalibratedAttentionClassifier(settings: settings).classify(.pose(sample))
            time = sample.time
        case .noFace(let sampleTime):
            signal = CalibratedAttentionClassifier(settings: settings).classify(.noFace)
            time = sampleTime
        case .ambiguous(let sampleTime):
            signal = CalibratedAttentionClassifier(settings: settings).classify(.ambiguous)
            time = sampleTime
        case .failed(let sampleTime):
            signal = .unknown
            time = sampleTime
        }

        state = mapDebouncedState(
            stateMachine.apply(RawAttentionSample(signal: signal, time: time)),
            signal: signal
        )
        return state
    }

    func updateSettings(_ settings: AttentionSettings) throws {
        try settingsStore.save(settings)
        self.settings = settings
        self.stateMachine = AttentionStateMachine(timing: settings.timing(for: settings.mode))
    }

    func resetCalibration() throws {
        try settingsStore.reset()
        settings = settingsStore.load()
        stateMachine = AttentionStateMachine(timing: settings.timing(for: settings.mode))
        state = .needsCalibration
    }

    private func resolvePermission() async -> Bool {
        switch permissionProvider.authorizationStatus() {
        case .granted:
            return true
        case .denied, .restricted:
            return false
        case .undetermined:
            return await permissionProvider.requestAccess()
        }
    }

    private func saveCalibration(_ snapshot: CalibrationSnapshot) -> Bool {
        var updatedSettings = settings.withCalibration(snapshot)
        updatedSettings.schemaVersion = AttentionSettings.currentSchemaVersion

        do {
            try settingsStore.save(updatedSettings)
            settings = updatedSettings
            stateMachine = AttentionStateMachine(timing: updatedSettings.timing(for: updatedSettings.mode))
            return true
        } catch {
            state = .unavailable
            return false
        }
    }

    private func mapDebouncedState(
        _ debouncedState: DebouncedAttentionState,
        signal: RawAttentionSignal
    ) -> AttentionMonitorState {
        switch signal {
        case .ambiguous, .unknown, .cameraPermissionDenied, .cameraUnavailable:
            return .unavailable
        case .uncalibrated:
            return .needsCalibration
        case .facing, .away, .noFace:
            break
        }

        switch debouncedState {
        case .facing:
            return .facing
        case .lookingAway:
            return .lookingAway
        case .noFaceDetected:
            return .noFaceDetected
        case .recovering:
            return .recovering
        case .unavailable:
            return .unavailable
        }
    }
}

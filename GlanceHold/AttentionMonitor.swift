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
    private var activeSessionID: UUID?

    private(set) var state: AttentionMonitorState
    private(set) var settings: AttentionSettings
    var stateDidChange: ((AttentionMonitorState, AttentionSettings) -> Void)?

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
            setState(.cameraPermissionDenied)
            return
        }

        guard settings.calibration != nil else {
            setState(.needsCalibration)
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        capture.frameHandler = { [weak self] frame in
            guard let self else {
                return
            }

            let observation = self.analyzer.analyze(frame)
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID else {
                    return
                }

                _ = self.applySample(observation)
            }
        }

        do {
            try await capture.start()
            isCaptureRunning = true
            setState(.ready)
        } catch CameraFrameCaptureError.unavailable {
            clearActiveCapture(sessionID: sessionID)
            setState(.cameraUnavailable)
        } catch {
            clearActiveCapture(sessionID: sessionID)
            setState(.unavailable)
        }
    }

    func stopMonitoring() {
        guard isCaptureRunning else {
            activeSessionID = nil
            capture.frameHandler = nil
            setState(.off)
            return
        }

        clearActiveCapture(sessionID: activeSessionID)
        setState(.off)
    }

    func startCalibration() {
        setState(.calibrating)
    }

    func captureCalibrationSampleSet(
        targetSampleCount: Int = 5,
        maximumFrameCount: Int = 30
    ) async -> CalibrationResult {
        guard await resolvePermission() else {
            setState(.cameraPermissionDenied)
            return .failed(previous: settings.calibration)
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        setState(.calibrating)

        var poseSamples: [PoseSample] = []
        var frameCount = 0

        let stream = AsyncStream<VisionAttentionObservation> { continuation in
            capture.frameHandler = { [weak self] frame in
                guard let self, self.activeSessionID == sessionID else {
                    return
                }

                continuation.yield(self.analyzer.analyze(frame))
            }
        }

        do {
            try await capture.start()
            isCaptureRunning = true
        } catch CameraFrameCaptureError.unavailable {
            clearActiveCapture(sessionID: sessionID)
            setState(.cameraUnavailable)
            return .failed(previous: settings.calibration)
        } catch {
            clearActiveCapture(sessionID: sessionID)
            setState(.unavailable)
            return .failed(previous: settings.calibration)
        }

        for await observation in stream {
            guard activeSessionID == sessionID else {
                return .failed(previous: settings.calibration)
            }

            frameCount += 1
            if case .pose(let sample) = observation {
                poseSamples.append(sample)
            }

            if poseSamples.count >= targetSampleCount || frameCount >= maximumFrameCount {
                break
            }
        }

        clearActiveCapture(sessionID: sessionID)
        return await startCalibration(samples: poseSamples)
    }

    func startCalibration(samples: [PoseSample]) async -> CalibrationResult {
        setState(.calibrating)

        let result = CalibrationModel.evaluate(samples: samples, existing: settings.calibration)
        switch result {
        case .accepted(let snapshot):
            if saveCalibration(snapshot) {
                setState(.ready)
            }
        case .needsReplacementConfirmation:
            setState(.ready)
        case .failed(let previous):
            setState(previous == nil ? .needsCalibration : .calibrationFailed(previousKept: true))
        }

        return result
    }

    func applyCalibrationReplacement(
        candidate: CalibrationSnapshot,
        existing: CalibrationSnapshot,
        decision: CalibrationReplacementDecision
    ) throws {
        let snapshot = CalibrationModel.resolveReplacement(
            candidate: candidate,
            existing: existing,
            decision: decision
        )
        try persistCalibration(snapshot)
        setState(.ready)
    }

    @discardableResult
    func applySample(_ observation: VisionAttentionObservation) -> AttentionMonitorState {
        guard settings.calibration != nil else {
            setState(.needsCalibration)
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

        setState(mapDebouncedState(
            stateMachine.apply(RawAttentionSample(signal: signal, time: time)),
            signal: signal
        ))
        return state
    }

    func updateSettings(_ settings: AttentionSettings) throws {
        try settingsStore.save(settings)
        self.settings = settings
        self.stateMachine = AttentionStateMachine(timing: settings.timing(for: settings.mode))
        stateDidChange?(state, self.settings)
    }

    func resetCalibration() throws {
        try settingsStore.reset()
        settings = settingsStore.load()
        stateMachine = AttentionStateMachine(timing: settings.timing(for: settings.mode))
        setState(.needsCalibration)
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
        do {
            try persistCalibration(snapshot)
            return true
        } catch {
            setState(.unavailable)
            return false
        }
    }

    private func persistCalibration(_ snapshot: CalibrationSnapshot) throws {
        var updatedSettings = settings.withCalibration(snapshot)
        updatedSettings.schemaVersion = AttentionSettings.currentSchemaVersion
        try settingsStore.save(updatedSettings)
        settings = updatedSettings
        stateMachine = AttentionStateMachine(timing: updatedSettings.timing(for: updatedSettings.mode))
        stateDidChange?(state, settings)
    }

    private func clearActiveCapture(sessionID: UUID?) {
        if activeSessionID == sessionID || sessionID == nil {
            activeSessionID = nil
        }
        capture.frameHandler = nil
        capture.stop()
        isCaptureRunning = false
    }

    private func setState(_ state: AttentionMonitorState) {
        self.state = state
        stateDidChange?(state, settings)
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

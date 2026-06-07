import Foundation
import os

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

private enum CalibrationCaptureEvent {
    case observation(VisionAttentionObservation)
    case timeout
}

private enum CalibrationCaptureEndReason: String {
    case targetReached
    case maximumFrames
    case maximumDuration
    case sessionCancelled
}

private struct CalibrationCaptureMetrics {
    var frameCount = 0
    var poseCount = 0
    var noFaceCount = 0
    var ambiguousCount = 0
    var failedCount = 0

    mutating func record(_ observation: VisionAttentionObservation) {
        frameCount += 1

        switch observation {
        case .pose:
            poseCount += 1
        case .noFace:
            noFaceCount += 1
        case .ambiguous:
            ambiguousCount += 1
        case .failed:
            failedCount += 1
        }
    }
}

final class AttentionMonitor {
    private static let logger = Logger(subsystem: "com.metatron.GlanceHold", category: "AttentionMonitor")

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
        targetSampleCount: Int = 10,
        maximumFrameCount: Int = 120,
        minimumCaptureDuration: TimeInterval = 1.2,
        maximumCaptureDuration: TimeInterval = 4.0
    ) async -> CalibrationResult {
        guard await resolvePermission() else {
            setState(.cameraPermissionDenied)
            return .failed(previous: settings.calibration)
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        setState(.calibrating)

        var poseSamples: [PoseSample] = []
        var metrics = CalibrationCaptureMetrics()
        var endReason = CalibrationCaptureEndReason.maximumDuration
        var streamContinuation: AsyncStream<CalibrationCaptureEvent>.Continuation?
        let startedAt = Date()

        Self.logger.info(
            "Calibration capture started targetPoseSamples=\(targetSampleCount, privacy: .public) maximumFrameCount=\(maximumFrameCount, privacy: .public) minimumDurationSeconds=\(minimumCaptureDuration, privacy: .public) maximumDurationSeconds=\(maximumCaptureDuration, privacy: .public)"
        )

        let stream = AsyncStream<CalibrationCaptureEvent> { continuation in
            streamContinuation = continuation
            capture.frameHandler = { [weak self] frame in
                guard let self, self.activeSessionID == sessionID else {
                    return
                }

                continuation.yield(.observation(self.analyzer.analyze(frame)))
            }
        }

        let timeoutTask = Task {
            let timeout = UInt64(max(0.0, maximumCaptureDuration) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: timeout)
                streamContinuation?.yield(.timeout)
            } catch {
                return
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

        defer {
            timeoutTask.cancel()
            streamContinuation?.finish()
        }

        for await event in stream {
            guard activeSessionID == sessionID else {
                endReason = .sessionCancelled
                clearActiveCapture(sessionID: sessionID)
                return .failed(previous: settings.calibration)
            }

            guard case .observation(let observation) = event else {
                endReason = .maximumDuration
                break
            }

            metrics.record(observation)
            if case .pose(let sample) = observation {
                poseSamples.append(sample)
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            if metrics.frameCount >= maximumFrameCount {
                endReason = .maximumFrames
                break
            }

            if elapsed >= maximumCaptureDuration {
                endReason = .maximumDuration
                break
            }

            if poseSamples.count >= targetSampleCount && elapsed >= minimumCaptureDuration {
                endReason = .targetReached
                break
            }
        }

        clearActiveCapture(sessionID: sessionID)
        return await finishCalibration(samples: poseSamples, captureMetrics: metrics, endReason: endReason)
    }

    func startCalibration(samples: [PoseSample]) async -> CalibrationResult {
        await finishCalibration(samples: samples, captureMetrics: nil, endReason: nil)
    }

    private func finishCalibration(
        samples: [PoseSample],
        captureMetrics: CalibrationCaptureMetrics?,
        endReason: CalibrationCaptureEndReason?
    ) async -> CalibrationResult {
        setState(.calibrating)

        let evaluation = CalibrationModel.evaluateDetailed(samples: samples, existing: settings.calibration)
        logCalibrationEnd(evaluation: evaluation, captureMetrics: captureMetrics, endReason: endReason)

        switch evaluation.result {
        case .accepted(let snapshot):
            if saveCalibration(snapshot) {
                setState(.ready)
            }
        case .needsReplacementConfirmation:
            setState(.ready)
        case .failed(let previous):
            setState(.calibrationFailed(previousKept: previous != nil))
        }

        return evaluation.result
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

    private func logCalibrationEnd(
        evaluation: CalibrationEvaluation,
        captureMetrics: CalibrationCaptureMetrics?,
        endReason: CalibrationCaptureEndReason?
    ) {
        let metrics = captureMetrics ?? CalibrationCaptureMetrics()
        let diagnostics = evaluation.diagnostics
        let quality = diagnostics.selectedWindowQuality.map { String(describing: $0) } ?? "none"
        let failureReason = diagnostics.failureReason?.rawValue ?? "none"
        let captureEndReason = endReason?.rawValue ?? "directSamples"
        let selectedSpread = diagnostics.selectedWindowSpreadDegrees.map { String(format: "%.3f", $0) } ?? "none"

        Self.logger.info(
            "Calibration attempt ended frames=\(metrics.frameCount, privacy: .public) poses=\(metrics.poseCount, privacy: .public) noFace=\(metrics.noFaceCount, privacy: .public) ambiguous=\(metrics.ambiguousCount, privacy: .public) failed=\(metrics.failedCount, privacy: .public) inputSamples=\(diagnostics.inputSampleCount, privacy: .public) selectedWindowSize=\(diagnostics.selectedWindowSampleCount, privacy: .public) selectedSpreadDegrees=\(selectedSpread, privacy: .public) selectedQuality=\(quality, privacy: .public) failureReason=\(failureReason, privacy: .public) captureEndReason=\(captureEndReason, privacy: .public)"
        )
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

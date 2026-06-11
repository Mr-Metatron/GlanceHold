import Foundation
import os

enum AttentionMonitorState: Equatable {
    case off
    case needsCalibration
    case calibrating
    case ready
    case monitoringPendingFirstSample
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
    private let diagnosticRecorder: DiagnosticRecording
    private let diagnosticMode: DiagnosticMode
    private let runtimeSummaryInterval: TimeInterval
    private var stateMachine: AttentionStateMachine
    private var isCaptureRunning = false
    private var activeSessionID: UUID?
    private var activeDiagnosticSession: DiagnosticSession?
    private var monitoringMetrics = DiagnosticRuntimeMetrics.empty
    private var monitoringStartedAt: TimeInterval?
    private var lastMonitoringMetricSampleAt: TimeInterval?
    private var lastPeriodicSummaryAt: TimeInterval?
    private let monitoringAnalysisInterval: TimeInterval = 0.2

    private(set) var state: AttentionMonitorState
    private(set) var settings: AttentionSettings
    var stateDidChange: ((AttentionMonitorState, AttentionSettings) -> Void)?
    var currentDiagnosticSession: DiagnosticSession? {
        activeDiagnosticSession
    }
    var diagnosticSessionDidChange: ((DiagnosticSession?) -> Void)?

    init(
        permissionProvider: CameraPermissionProviding,
        settingsStore: AttentionSettingsStoring,
        capture: CameraFrameCapturing,
        analyzer: VisionAttentionAnalyzing,
        diagnosticRecorder: DiagnosticRecording = NoOpDiagnosticRecorder(),
        diagnosticMode: DiagnosticMode = .default,
        runtimeSummaryInterval: TimeInterval = 5.0
    ) {
        self.permissionProvider = permissionProvider
        self.settingsStore = settingsStore
        self.capture = capture
        self.analyzer = analyzer
        self.diagnosticRecorder = diagnosticRecorder
        self.diagnosticMode = diagnosticMode
        self.runtimeSummaryInterval = runtimeSummaryInterval

        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.stateMachine = AttentionStateMachine(timing: loadedSettings.timing(for: loadedSettings.mode))
        self.state = loadedSettings.calibration == nil ? .needsCalibration : .ready
    }

    func startMonitoring() async {
        guard !isCaptureRunning else {
            return
        }

        guard await resolvePermission() else {
            setState(.cameraPermissionDenied)
            return
        }

        guard settings.calibration != nil else {
            setState(.needsCalibration)
            return
        }

        let sessionID = UUID()
        let diagnosticSession = DiagnosticSession(id: sessionID, kind: .monitoring)
        activeSessionID = sessionID
        activeDiagnosticSession = diagnosticSession
        monitoringMetrics = .empty
        monitoringStartedAt = nil
        lastMonitoringMetricSampleAt = nil
        lastPeriodicSummaryAt = nil
        diagnosticRecorder.record(DiagnosticEventRequest(category: .monitoring, name: .sessionStarted), in: diagnosticSession)

        var lastAnalyzedMonitoringFrameTime: TimeInterval?

        capture.frameHandler = { [weak self] frame in
            guard let self else {
                return
            }

            self.monitoringMetrics.framesReceived += 1
            self.lastMonitoringMetricSampleAt = frame.time

            if let lastAnalyzedMonitoringFrameTime,
               frame.time - lastAnalyzedMonitoringFrameTime < self.monitoringAnalysisInterval {
                self.monitoringMetrics.skippedSamples += 1
                return
            }

            lastAnalyzedMonitoringFrameTime = frame.time
            let analysisStartedAt = Date()
            let observation = self.analyzer.analyze(frame)
            let latencyMilliseconds = Date().timeIntervalSince(analysisStartedAt) * 1_000.0
            self.monitoringMetrics.framesAnalyzed += 1
            self.monitoringMetrics.analysisLatencyMillisecondsTotal += latencyMilliseconds
            self.monitoringMetrics.analysisLatencyMillisecondsMax = max(
                self.monitoringMetrics.analysisLatencyMillisecondsMax,
                latencyMilliseconds
            )

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard self.activeSessionID == sessionID else {
                    self.monitoringMetrics.droppedSamples += 1
                    return
                }

                _ = self.applySample(observation)
            }
        }

        do {
            try await capture.start()
            isCaptureRunning = true
            diagnosticSessionDidChange?(diagnosticSession)
            setState(.monitoringPendingFirstSample)
        } catch CameraFrameCaptureError.unavailable {
            recordFailure(category: .camera, in: diagnosticSession)
            clearActiveCapture(sessionID: sessionID)
            clearActiveDiagnosticSession(diagnosticSession)
            setState(.cameraUnavailable)
        } catch {
            recordFailure(category: .monitoring, in: diagnosticSession)
            clearActiveCapture(sessionID: sessionID)
            clearActiveDiagnosticSession(diagnosticSession)
            setState(.unavailable)
        }
    }

    func stopMonitoring() {
        finishMonitoringDiagnostics()

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
        let diagnosticSession = DiagnosticSession(id: sessionID, kind: .calibration)
        activeSessionID = sessionID
        diagnosticRecorder.record(DiagnosticEventRequest(category: .calibration, name: .sessionStarted), in: diagnosticSession)
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
            recordFailure(category: .camera, in: diagnosticSession)
            clearActiveCapture(sessionID: sessionID)
            setState(.cameraUnavailable)
            return .failed(previous: settings.calibration)
        } catch {
            recordFailure(category: .calibration, in: diagnosticSession)
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
        return await finishCalibration(
            samples: poseSamples,
            captureMetrics: metrics,
            endReason: endReason,
            diagnosticSession: diagnosticSession
        )
    }

    func startCalibration(samples: [PoseSample]) async -> CalibrationResult {
        let diagnosticSession = DiagnosticSession(kind: .calibration)
        diagnosticRecorder.record(DiagnosticEventRequest(category: .calibration, name: .sessionStarted), in: diagnosticSession)
        return await finishCalibration(
            samples: samples,
            captureMetrics: nil,
            endReason: nil,
            diagnosticSession: diagnosticSession
        )
    }

    private func finishCalibration(
        samples: [PoseSample],
        captureMetrics: CalibrationCaptureMetrics?,
        endReason: CalibrationCaptureEndReason?,
        diagnosticSession: DiagnosticSession
    ) async -> CalibrationResult {
        setState(.calibrating)

        let evaluation = CalibrationModel.evaluateDetailed(samples: samples, existing: settings.calibration)
        logCalibrationEnd(
            evaluation: evaluation,
            captureMetrics: captureMetrics,
            endReason: endReason,
            diagnosticSession: diagnosticSession
        )

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

        let previousVisibleState = state
        let transition = stateMachine.applyWithDiagnostics(RawAttentionSample(signal: signal, time: time))
        setState(mapDebouncedState(transition.nextState, signal: signal))
        if state != previousVisibleState {
            monitoringMetrics.semanticStateChanges += 1
        }
        recordAttentionDiagnostics(for: transition, sampleTime: time)
        return state
    }

    func updateSettings(_ settings: AttentionSettings) throws {
        try settingsStore.save(settings)
        self.settings = settings
        self.stateMachine = AttentionStateMachine(timing: settings.timing(for: settings.mode))
        stateDidChange?(state, self.settings)
    }

    func resetCalibration() throws {
        var updatedSettings = settings.withCalibration(nil)
        updatedSettings.schemaVersion = AttentionSettings.currentSchemaVersion
        try settingsStore.save(updatedSettings)
        settings = updatedSettings
        stateMachine = AttentionStateMachine(timing: updatedSettings.timing(for: updatedSettings.mode))
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
        endReason: CalibrationCaptureEndReason?,
        diagnosticSession: DiagnosticSession
    ) {
        let metrics = captureMetrics ?? CalibrationCaptureMetrics()
        let diagnostics = evaluation.diagnostics
        let quality = diagnostics.selectedWindowQuality.map { String(describing: $0) } ?? "none"
        let failureReason = diagnostics.failureReason?.rawValue ?? "none"
        let captureEndReason = endReason?.rawValue ?? "directSamples"

        diagnosticRecorder.record(
            DiagnosticEventRequest(
                category: .calibration,
                name: .calibrationEnded,
                fields: [
                    diagnosticField(.calibrationFrameCount, .int(metrics.frameCount)),
                    diagnosticField(.calibrationPoseCount, .int(metrics.poseCount)),
                    diagnosticField(.calibrationNoFaceCount, .int(metrics.noFaceCount)),
                    diagnosticField(.calibrationAmbiguousCount, .int(metrics.ambiguousCount)),
                    diagnosticField(.calibrationFailedCount, .int(metrics.failedCount)),
                    diagnosticField(.inputSampleCount, .int(diagnostics.inputSampleCount)),
                    diagnosticField(.selectedWindowSampleCount, .int(diagnostics.selectedWindowSampleCount)),
                    diagnosticField(
                        .selectedWindowDurationSeconds,
                        .double(diagnostics.selectedWindowDurationSeconds ?? 0.0)
                    ),
                    diagnosticField(.selectedWindowSpreadDegrees, .double(diagnostics.selectedWindowSpreadDegrees ?? 0.0)),
                    diagnosticField(.selectedWindowQuality, .string(quality)),
                    diagnosticField(.failureReason, .string(failureReason)),
                    diagnosticField(.captureEndReason, .string(captureEndReason))
                ]
            ),
            in: diagnosticSession
        )
    }

    private func finishMonitoringDiagnostics() {
        guard let diagnosticSession = activeDiagnosticSession else {
            return
        }

        diagnosticRecorder.record(
            DiagnosticEventRequest.runtimeSummary(finalizedMetrics(at: nil), periodic: false, source: .attention),
            in: diagnosticSession
        )
        diagnosticRecorder.record(
            DiagnosticEventRequest(category: .monitoring, name: .sessionStopped),
            in: diagnosticSession
        )
        activeDiagnosticSession = nil
        diagnosticSessionDidChange?(nil)
        monitoringStartedAt = nil
        lastMonitoringMetricSampleAt = nil
        lastPeriodicSummaryAt = nil
    }

    private func recordFailure(category: DiagnosticCategory, in session: DiagnosticSession) {
        diagnosticRecorder.record(DiagnosticEventRequest(category: category, name: .failure), in: session)
    }

    private func recordAttentionDiagnostics(
        for transition: AttentionStateMachineResult,
        sampleTime: TimeInterval
    ) {
        guard let diagnosticSession = activeDiagnosticSession else {
            return
        }

        if monitoringStartedAt == nil {
            monitoringStartedAt = sampleTime
            lastPeriodicSummaryAt = sampleTime
        }

        diagnosticRecorder.record(
            DiagnosticEventRequest(
                category: .attention,
                name: .attentionTransition,
                fields: attentionFields(for: transition)
            ),
            in: diagnosticSession
        )
        recordPeriodicRuntimeSummaryIfNeeded(at: sampleTime, in: diagnosticSession)
    }

    private func recordPeriodicRuntimeSummaryIfNeeded(at sampleTime: TimeInterval, in session: DiagnosticSession) {
        guard diagnosticMode == .diagnostic else {
            return
        }

        let lastSummary = lastPeriodicSummaryAt ?? sampleTime
        guard sampleTime - lastSummary >= runtimeSummaryInterval else {
            return
        }

        diagnosticRecorder.record(
            DiagnosticEventRequest.runtimeSummary(finalizedMetrics(at: sampleTime), periodic: true, source: .attention),
            in: session
        )
        lastPeriodicSummaryAt = sampleTime
    }

    private func finalizedMetrics(at sampleTime: TimeInterval?) -> DiagnosticRuntimeMetrics {
        var metrics = monitoringMetrics
        let endTime = sampleTime ?? lastMonitoringMetricSampleAt ?? Date().timeIntervalSince1970
        if let monitoringStartedAt {
            let duration = max(endTime - monitoringStartedAt, 0.0)
            if duration > 0.0 {
                metrics.analyzerRateHz = Double(metrics.framesAnalyzed) / duration
            }
        }
        return metrics
    }

    private func attentionFields(for transition: AttentionStateMachineResult) -> [DiagnosticField] {
        var fields = [
            diagnosticField(.rawSignal, .string(String(describing: transition.rawSignal))),
            diagnosticField(.previousState, .string(String(describing: transition.previousState))),
            diagnosticField(.nextState, .string(String(describing: transition.nextState))),
            diagnosticField(.previousEmittedState, .string(String(describing: transition.previousEmittedState))),
            diagnosticField(.transitionReason, .string(String(describing: transition.reason)))
        ]

        if let candidateSignal = transition.candidateSignal {
            fields.append(diagnosticField(.candidateSignal, .string(String(describing: candidateSignal))))
        }
        if let candidateStartedAt = transition.candidateStartedAt {
            fields.append(diagnosticField(.candidateStartedAt, .double(candidateStartedAt)))
        }
        if let elapsedSinceCandidateStart = transition.elapsedSinceCandidateStart {
            fields.append(diagnosticField(.elapsedSinceCandidateStart, .double(elapsedSinceCandidateStart)))
        }
        if let requiredThreshold = transition.requiredThreshold {
            fields.append(diagnosticField(.requiredThreshold, .double(requiredThreshold)))
        }

        return fields
    }

    private func diagnosticField(_ name: DiagnosticFieldName, _ value: DiagnosticFieldValue) -> DiagnosticField {
        guard let field = try? DiagnosticField(name, value) else {
            preconditionFailure("Static attention diagnostic field failed validation.")
        }
        return field
    }

    private func clearActiveCapture(sessionID: UUID?) {
        if activeSessionID == sessionID || sessionID == nil {
            activeSessionID = nil
        }
        capture.frameHandler = nil
        capture.stop()
        isCaptureRunning = false
    }

    private func clearActiveDiagnosticSession(_ session: DiagnosticSession) {
        guard activeDiagnosticSession === session else {
            return
        }

        activeDiagnosticSession = nil
        diagnosticSessionDidChange?(nil)
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
        case .uncalibrated:
            return .needsCalibration
        case .cameraPermissionDenied:
            return .cameraPermissionDenied
        case .cameraUnavailable:
            return .cameraUnavailable
        case .ambiguous, .unknown, .facing, .away, .noFace:
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

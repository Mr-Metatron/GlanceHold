import Foundation

struct PlaybackCoordinatorState: Equatable {
    var isPlayerControllable: Bool
    var playerSnapshot: PlayerSnapshot
    var stoppedReason: StopMonitoringReason?

    static var unavailable: PlaybackCoordinatorState {
        PlaybackCoordinatorState(isPlayerControllable: false, playerSnapshot: .playerUnavailable)
    }

    static var setupNeeded: PlaybackCoordinatorState {
        PlaybackCoordinatorState(isPlayerControllable: false, playerSnapshot: .setupNeeded)
    }
}

enum PlaybackCompletedAction: Equatable {
    case heldSpeedAtOne
    case restoredSpeed(Double)
    case pausedByGlanceHold
    case resumedPlayback
}

final class PlaybackCoordinator {
    private static let speedEpsilon = 0.000_001

    private let mode: MonitoringMode
    private let adapter: IINAPlaybackAdapting
    private let diagnosticRecorder: DiagnosticRecording
    private let diagnosticMode: DiagnosticMode
    private var policy: PlaybackPolicy
    private var suppressCommandsUntilValidSnapshot = false
    private var monitoringSessionActive = false
    private var activeDiagnosticSession: DiagnosticSession?
    private var playbackMetrics = DiagnosticRuntimeMetrics.empty

    private(set) var state: PlaybackCoordinatorState {
        didSet {
            stateDidChange?(state)
        }
    }

    var stateDidChange: ((PlaybackCoordinatorState) -> Void)?
    var stopMonitoringRequested: ((StopMonitoringReason) -> Void)?
    var playbackActionDidComplete: ((PlaybackCompletedAction) -> Void)?

    init(
        mode: MonitoringMode,
        adapter: IINAPlaybackAdapting,
        diagnosticRecorder: DiagnosticRecording = NoOpDiagnosticRecorder(),
        diagnosticMode: DiagnosticMode = .default,
        diagnosticSession: DiagnosticSession? = nil
    ) {
        self.mode = mode
        self.adapter = adapter
        self.diagnosticRecorder = diagnosticRecorder
        self.diagnosticMode = diagnosticMode
        self.activeDiagnosticSession = diagnosticSession
        self.policy = PlaybackPolicy(mode: mode)
        self.state = .unavailable
    }

    func setDiagnosticSession(_ session: DiagnosticSession?) {
        activeDiagnosticSession = session
        playbackMetrics = .empty
    }

    func stopMonitoring() {
        monitoringSessionActive = false
        recordFinalPlaybackSummary()
        resetPolicy()
        state = .unavailable
    }

    func refreshPlayerState() async {
        let snapshot = await readSnapshot()
        guard !Task.isCancelled else {
            return
        }
        applyReadOnlyPlayerSnapshot(snapshot)
    }

    func applyPushedPlayerSnapshot(_ snapshot: PlayerSnapshot) {
        playbackMetrics.playbackSnapshots += 1
        applyReadOnlyPlayerSnapshot(snapshot)
    }

    func observePlayerStatusUpdates() async {
        for await event in adapter.statusEvents() {
            if Task.isCancelled {
                return
            }

            switch event {
            case let .status(snapshot):
                applyPushedPlayerSnapshot(snapshot)
            case .heartbeat:
                continue
            }
        }
    }

    func handleAttentionState(_ state: DebouncedAttentionState) async {
        monitoringSessionActive = true
        let snapshot = await readSnapshot()
        guard !Task.isCancelled else {
            return
        }
        let isControllable = isPlayerControllable(snapshot)

        if self.state.stoppedReason != nil {
            applyReadOnlyPlayerSnapshot(snapshot)
            return
        }

        if isControllable, applyObservedPlayerSnapshotForManualStopIfNeeded(snapshot, monitoringActive: true) {
            return
        }

        updateState(snapshot: snapshot, isPlayerControllable: isControllable)

        guard isControllable else {
            return
        }

        if suppressCommandsUntilValidSnapshot {
            suppressCommandsUntilValidSnapshot = false
            return
        }

        let result = policy.apply(attention: state, player: snapshot)
        guard let intent = result.intents.first else {
            return
        }

        if case let .stopMonitoring(reason) = intent {
            handleStopMonitoring(reason: reason, snapshot: snapshot)
            return
        }

        guard !Task.isCancelled else {
            return
        }

        do {
            playbackMetrics.playbackCommands += 1
            try await adapter.execute(intent)
            guard !Task.isCancelled else {
                return
            }
            let confirmation = await readSnapshot()
            guard !Task.isCancelled else {
                return
            }
            guard confirms(intent: intent, with: confirmation) else {
                recordPlaybackAction(
                    snapshot: snapshot,
                    intent: intent,
                    confirmationOutcome: "failed",
                    completedAction: nil,
                    errorCategory: "confirmationFailed"
                )
                markNotControllable(snapshot: confirmation)
                return
            }

            updateState(snapshot: confirmation, isPlayerControllable: isPlayerControllable(confirmation))
            if let completedAction = completedAction(for: intent) {
                recordPlaybackAction(
                    snapshot: snapshot,
                    intent: intent,
                    confirmationOutcome: "confirmed",
                    completedAction: completedAction,
                    errorCategory: "none"
                )
                playbackActionDidComplete?(completedAction)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            recordPlaybackAction(
                snapshot: snapshot,
                intent: intent,
                confirmationOutcome: "notAttempted",
                completedAction: nil,
                errorCategory: "commandFailed"
            )
            markNotControllable(snapshot: snapshot)
        }
    }

    private func readSnapshot() async -> PlayerSnapshot {
        let snapshot = await adapter.snapshot()
        playbackMetrics.playbackSnapshots += 1
        return snapshot
    }

    private func isPlayerControllable(_ snapshot: PlayerSnapshot) -> Bool {
        switch snapshot.playbackState {
        case .playing, .paused:
            return snapshot.speed != nil
        case .idle, .setupNeeded, .playerUnavailable:
            return false
        }
    }

    private func confirms(intent: PlaybackIntent, with snapshot: PlayerSnapshot) -> Bool {
        switch intent {
        case .holdSpeedAtOne:
            return snapshot.playbackState == .playing && approximatelyEqual(snapshot.speed, 1.0)
        case let .restoreSpeed(speed):
            return snapshot.playbackState == .playing && approximatelyEqual(snapshot.speed, speed)
        case .pause:
            return snapshot.playbackState == .paused && snapshot.speed != nil
        case .resume:
            return snapshot.playbackState == .playing && snapshot.speed != nil
        case .stopMonitoring:
            return false
        }
    }

    private func completedAction(for intent: PlaybackIntent) -> PlaybackCompletedAction? {
        switch intent {
        case .holdSpeedAtOne:
            .heldSpeedAtOne
        case let .restoreSpeed(speed):
            .restoredSpeed(speed)
        case .pause:
            .pausedByGlanceHold
        case .resume:
            .resumedPlayback
        case .stopMonitoring:
            nil
        }
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs - rhs) <= Self.speedEpsilon
    }

    private func markNotControllable(snapshot: PlayerSnapshot) {
        resetPolicy()
        suppressCommandsUntilValidSnapshot = true
        updateState(snapshot: snapshot, isPlayerControllable: false)
    }

    private func resetPolicy() {
        policy = PlaybackPolicy(mode: mode)
    }

    private func applyReadOnlyPlayerSnapshot(_ snapshot: PlayerSnapshot) {
        let isControllable = isPlayerControllable(snapshot)
        if let stoppedReason = state.stoppedReason {
            state = PlaybackCoordinatorState(
                isPlayerControllable: false,
                playerSnapshot: snapshot,
                stoppedReason: stoppedReason
            )
            return
        }

        if isControllable, applyObservedPlayerSnapshotForManualStopIfNeeded(snapshot, monitoringActive: monitoringSessionActive) {
            return
        }

        if isControllable {
            suppressCommandsUntilValidSnapshot = false
        }
        updateState(snapshot: snapshot, isPlayerControllable: isControllable)
    }

    @discardableResult
    private func applyObservedPlayerSnapshotForManualStopIfNeeded(
        _ snapshot: PlayerSnapshot,
        monitoringActive: Bool
    ) -> Bool {
        let result = policy.applyObservedPlayerSnapshot(snapshot, monitoringActive: monitoringActive)
        guard case let .stopMonitoring(reason)? = result.intents.first else {
            return false
        }

        handleStopMonitoring(reason: reason, snapshot: snapshot)
        return true
    }

    private func handleStopMonitoring(reason: StopMonitoringReason, snapshot: PlayerSnapshot) {
        monitoringSessionActive = false
        resetPolicy()
        state = PlaybackCoordinatorState(
            isPlayerControllable: false,
            playerSnapshot: snapshot,
            stoppedReason: reason
        )
        stopMonitoringRequested?(reason)
    }

    private func updateState(snapshot: PlayerSnapshot, isPlayerControllable: Bool) {
        state = PlaybackCoordinatorState(
            isPlayerControllable: isPlayerControllable,
            playerSnapshot: snapshot,
            stoppedReason: nil
        )
    }

    private func recordFinalPlaybackSummary() {
        guard let diagnosticSession = activeDiagnosticSession else {
            return
        }

        diagnosticRecorder.record(
            DiagnosticEventRequest.runtimeSummary(playbackMetrics, periodic: false),
            in: diagnosticSession
        )
        activeDiagnosticSession = nil
    }

    private func recordPlaybackAction(
        snapshot: PlayerSnapshot,
        intent: PlaybackIntent,
        confirmationOutcome: String,
        completedAction: PlaybackCompletedAction?,
        errorCategory: String
    ) {
        guard diagnosticMode == .diagnostic, let diagnosticSession = activeDiagnosticSession else {
            return
        }

        diagnosticRecorder.record(
            DiagnosticEventRequest(
                category: .playback,
                name: .playbackAction,
                fields: [
                    diagnosticField(.snapshotState, .string(snapshot.playbackState.diagnosticName)),
                    diagnosticField(.speedPresent, .bool(snapshot.speed != nil)),
                    diagnosticField(.intentType, .string(intent.diagnosticName)),
                    diagnosticField(.commandType, .string(intent.diagnosticName)),
                    diagnosticField(.confirmationOutcome, .string(confirmationOutcome)),
                    diagnosticField(.completedActionEmitted, .string(completedAction?.diagnosticName ?? "none")),
                    diagnosticField(.errorCategory, .string(errorCategory))
                ]
            ),
            in: diagnosticSession
        )
    }

    private func diagnosticField(_ name: DiagnosticFieldName, _ value: DiagnosticFieldValue) -> DiagnosticField {
        guard let field = try? DiagnosticField(name, value) else {
            preconditionFailure("Static playback diagnostic field failed validation.")
        }

        return field
    }
}

private extension PlayerPlaybackState {
    var diagnosticName: String {
        switch self {
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .idle:
            "idle"
        case .setupNeeded:
            "setupNeeded"
        case .playerUnavailable:
            "playerUnavailable"
        }
    }
}

private extension PlaybackIntent {
    var diagnosticName: String {
        switch self {
        case .holdSpeedAtOne:
            "holdSpeedAtOne"
        case .restoreSpeed:
            "restoreSpeed"
        case .pause:
            "pause"
        case .resume:
            "resume"
        case .stopMonitoring:
            "stopMonitoring"
        }
    }
}

private extension PlaybackCompletedAction {
    var diagnosticName: String {
        switch self {
        case .heldSpeedAtOne:
            "heldSpeedAtOne"
        case .restoredSpeed:
            "restoredSpeed"
        case .pausedByGlanceHold:
            "pausedByGlanceHold"
        case .resumedPlayback:
            "resumedPlayback"
        }
    }
}

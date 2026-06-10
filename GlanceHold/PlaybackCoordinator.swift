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
    private var monitoringGeneration = UUID()
    private var activeDiagnosticSession: DiagnosticSession?
    private var playbackMetrics = DiagnosticRuntimeMetrics.empty
    private var playbackNoOpAggregates: [PlaybackNoOpReason: PlaybackNoOpAggregate] = [:]

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
        playbackNoOpAggregates.removeAll()
    }

    func stopMonitoring() {
        monitoringGeneration = UUID()
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

    func recordSuppressedRepeatedStableStateNoCommand(_ state: DebouncedAttentionState) {
        recordPlaybackNoOp(
            reason: .repeatedStableStateNoCommand,
            breadcrumb: PlaybackNoOpBreadcrumb(
                attentionState: state.diagnosticName,
                snapshotState: "notRead",
                speedPresent: false,
                intentType: "none"
            )
        )
    }

    func handleAttentionState(_ state: DebouncedAttentionState) async {
        let generation = monitoringGeneration
        guard canStartAttentionSideEffect(startedIn: generation) else {
            return
        }

        monitoringSessionActive = true
        let snapshot = await readSnapshot()
        guard canStartAttentionSideEffect(startedIn: generation) else {
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
            recordPlaybackNoOp(
                reason: noOpReasonForUncontrollableSnapshot(snapshot),
                attentionState: state,
                snapshot: snapshot,
                intent: nil
            )
            return
        }

        if suppressCommandsUntilValidSnapshot {
            suppressCommandsUntilValidSnapshot = false
            return
        }

        let result = policy.apply(attention: state, player: snapshot)
        guard let intent = result.intents.first else {
            recordPlaybackNoOp(
                reason: noOpReasonForNoIntent(attentionState: state),
                attentionState: state,
                snapshot: snapshot,
                intent: nil
            )
            return
        }

        if case let .stopMonitoring(reason) = intent {
            handleStopMonitoring(reason: reason, snapshot: snapshot)
            return
        }

        guard canStartAttentionSideEffect(startedIn: generation) else {
            return
        }

        do {
            playbackMetrics.playbackCommands += 1
            try await adapter.execute(intent)
            guard isSameAttentionGeneration(startedIn: generation) else {
                return
            }

            let confirmation = await readSnapshot()
            guard isSameAttentionGeneration(startedIn: generation) else {
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
            guard isSameAttentionGeneration(startedIn: generation) else {
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

    private func canStartAttentionSideEffect(startedIn generation: UUID) -> Bool {
        !Task.isCancelled && isSameAttentionGeneration(startedIn: generation)
    }

    private func isSameAttentionGeneration(startedIn generation: UUID) -> Bool {
        generation == monitoringGeneration
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

        recordPlaybackNoOpSummaries(in: diagnosticSession)
        diagnosticRecorder.record(
            DiagnosticEventRequest.runtimeSummary(playbackMetrics, periodic: false, source: .playback),
            in: diagnosticSession
        )
        activeDiagnosticSession = nil
        playbackNoOpAggregates.removeAll()
    }

    private func noOpReasonForUncontrollableSnapshot(_ snapshot: PlayerSnapshot) -> PlaybackNoOpReason {
        switch snapshot.playbackState {
        case .playing, .paused:
            snapshot.speed == nil ? .missingSpeed : .playerNotControllable
        case .idle, .setupNeeded, .playerUnavailable:
            .playerNotControllable
        }
    }

    private func noOpReasonForNoIntent(attentionState: DebouncedAttentionState) -> PlaybackNoOpReason {
        switch attentionState {
        case .recovering:
            .recoveringNoCommand
        case .facing, .lookingAway, .noFaceDetected, .unavailable:
            .policyEvaluatedWithoutIntent
        }
    }

    private func recordPlaybackNoOp(
        reason: PlaybackNoOpReason,
        attentionState: DebouncedAttentionState,
        snapshot: PlayerSnapshot,
        intent: PlaybackIntent?
    ) {
        guard diagnosticMode == .diagnostic, activeDiagnosticSession != nil else {
            return
        }

        let breadcrumb = PlaybackNoOpBreadcrumb(
            attentionState: attentionState.diagnosticName,
            snapshotState: snapshot.playbackState.diagnosticName,
            speedPresent: snapshot.speed != nil,
            intentType: intent?.diagnosticName ?? "none"
        )
        recordPlaybackNoOp(reason: reason, breadcrumb: breadcrumb)
    }

    private func recordPlaybackNoOp(reason: PlaybackNoOpReason, breadcrumb: PlaybackNoOpBreadcrumb) {
        guard diagnosticMode == .diagnostic, activeDiagnosticSession != nil else {
            return
        }

        playbackNoOpAggregates[reason, default: PlaybackNoOpAggregate(first: breadcrumb)].record(breadcrumb)
    }

    private func recordPlaybackNoOpSummaries(in diagnosticSession: DiagnosticSession) {
        guard diagnosticMode == .diagnostic else {
            return
        }

        for reason in PlaybackNoOpReason.allCases {
            guard let aggregate = playbackNoOpAggregates[reason] else {
                continue
            }

            diagnosticRecorder.record(
                DiagnosticEventRequest(
                    category: .playback,
                    name: .playbackNoOpSummary,
                    fields: [
                        diagnosticField(.noOpReason, .string(reason.rawValue)),
                        diagnosticField(.noOpCount, .int(aggregate.count)),
                        diagnosticField(.firstAttentionState, .string(aggregate.first.attentionState)),
                        diagnosticField(.latestAttentionState, .string(aggregate.latest.attentionState)),
                        diagnosticField(.firstSnapshotState, .string(aggregate.first.snapshotState)),
                        diagnosticField(.latestSnapshotState, .string(aggregate.latest.snapshotState)),
                        diagnosticField(.firstSpeedPresent, .bool(aggregate.first.speedPresent)),
                        diagnosticField(.latestSpeedPresent, .bool(aggregate.latest.speedPresent)),
                        diagnosticField(.firstIntentType, .string(aggregate.first.intentType)),
                        diagnosticField(.latestIntentType, .string(aggregate.latest.intentType))
                    ]
                ),
                in: diagnosticSession
            )
        }
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

private enum PlaybackNoOpReason: String, CaseIterable {
    case missingSpeed
    case playerNotControllable
    case recoveringNoCommand
    case repeatedStableStateNoCommand
    case policyEvaluatedWithoutIntent
}

private struct PlaybackNoOpBreadcrumb: Equatable {
    var attentionState: String
    var snapshotState: String
    var speedPresent: Bool
    var intentType: String
}

private struct PlaybackNoOpAggregate: Equatable {
    var count: Int
    var first: PlaybackNoOpBreadcrumb
    var latest: PlaybackNoOpBreadcrumb

    init(first: PlaybackNoOpBreadcrumb) {
        self.count = 0
        self.first = first
        self.latest = first
    }

    mutating func record(_ breadcrumb: PlaybackNoOpBreadcrumb) {
        count += 1
        latest = breadcrumb
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

private extension DebouncedAttentionState {
    var diagnosticName: String {
        switch self {
        case .facing:
            "facing"
        case .lookingAway:
            "lookingAway"
        case .noFaceDetected:
            "noFaceDetected"
        case .recovering:
            "recovering"
        case .unavailable:
            "unavailable"
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

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
    private var pendingConfirmation: PendingPlaybackConfirmation?
    private var activeDiagnosticSession: DiagnosticSession?
    private var playbackMetrics = DiagnosticRuntimeMetrics.empty
    private var playbackNoOpAggregates: [PlaybackNoOpReason: PlaybackNoOpAggregate] = [:]

    private(set) var state: PlaybackCoordinatorState

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

    func invalidateInFlightAttentionHandling() {
        monitoringGeneration = UUID()
    }

    func stopMonitoring() {
        monitoringGeneration = UUID()
        monitoringSessionActive = false
        recordFinalPlaybackSummary()
        resetPolicy()
        setState(.unavailable)
    }

    func refreshPlayerState() async {
        let generation = monitoringGeneration
        guard let snapshot = await readSnapshot(startedIn: generation) else {
            return
        }
        guard canStartAttentionSideEffect(startedIn: generation) else {
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
        guard let snapshot = await readSnapshot(startedIn: generation) else {
            return
        }
        guard canStartAttentionSideEffect(startedIn: generation) else {
            return
        }

        let isControllable = isPlayerControllable(snapshot)

        if self.state.stoppedReason != nil {
            applyReadOnlyPlayerSnapshot(snapshot, startedIn: generation)
            return
        }

        if isControllable, applyObservedPlayerSnapshotForManualStopIfNeeded(
            snapshot,
            monitoringActive: true,
            startedIn: generation
        ) {
            return
        }

        updateState(snapshot: snapshot, isPlayerControllable: isControllable, startedIn: generation)

        guard isControllable else {
            recordPlaybackNoOp(
                reason: noOpReasonForUncontrollableSnapshot(snapshot),
                attentionState: state,
                snapshot: snapshot,
                intent: nil,
                startedIn: generation
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
                intent: nil,
                startedIn: generation
            )
            return
        }

        if case let .stopMonitoring(reason) = intent {
            handleStopMonitoring(reason: reason, snapshot: snapshot, startedIn: generation)
            return
        }

        guard canStartAttentionSideEffect(startedIn: generation) else {
            return
        }

        do {
            beginPendingConfirmation(intent: intent, sourceSnapshot: snapshot, startedIn: generation)
            playbackMetrics.playbackCommands += 1
            try await adapter.execute(intent)
            guard canStartAttentionSideEffect(startedIn: generation) else {
                return
            }

            guard let confirmation = await readSnapshot(startedIn: generation) else {
                return
            }

            if confirms(intent: intent, with: confirmation) {
                completeConfirmedCommand(
                    intent: intent,
                    sourceSnapshot: snapshot,
                    confirmation: confirmation,
                    startedIn: generation
                )
                return
            }

            guard isTransientUntrustedConfirmation(confirmation, for: intent),
                  let retryConfirmation = await readSnapshot(startedIn: generation) else {
                recordPlaybackAction(
                    snapshot: snapshot,
                    intent: intent,
                    confirmationOutcome: "failed",
                    completedAction: nil,
                    errorCategory: "confirmationFailed",
                    startedIn: generation
                )
                markNotControllable(snapshot: confirmation, startedIn: generation)
                return
            }

            resolveRetriedConfirmation(
                retryConfirmation,
                intent: intent,
                sourceSnapshot: snapshot,
                startedIn: generation
            )
        } catch {
            guard canStartAttentionSideEffect(startedIn: generation) else {
                return
            }

            recordPlaybackAction(
                snapshot: snapshot,
                intent: intent,
                confirmationOutcome: "notAttempted",
                completedAction: nil,
                errorCategory: "commandFailed",
                startedIn: generation
            )
            markNotControllable(snapshot: snapshot, startedIn: generation)
        }
    }

    private func beginPendingConfirmation(
        intent: PlaybackIntent,
        sourceSnapshot: PlayerSnapshot,
        startedIn generation: UUID
    ) {
        policy.beginPendingConfirmation(for: intent)
        pendingConfirmation = PendingPlaybackConfirmation(
            intent: intent,
            sourceSnapshot: sourceSnapshot,
            generation: generation
        )
    }

    private func completeConfirmedCommand(
        intent: PlaybackIntent,
        sourceSnapshot: PlayerSnapshot,
        confirmation: PlayerSnapshot,
        startedIn generation: UUID
    ) {
        policy.resolvePendingConfirmation(for: intent)
        pendingConfirmation = nil
        updateState(
            snapshot: confirmation,
            isPlayerControllable: isPlayerControllable(confirmation),
            startedIn: generation
        )
        if let completedAction = completedAction(for: intent) {
            recordPlaybackAction(
                snapshot: sourceSnapshot,
                intent: intent,
                confirmationOutcome: "confirmed",
                completedAction: completedAction,
                errorCategory: "none",
                startedIn: generation
            )
            emitPlaybackActionDidComplete(completedAction, startedIn: generation)
        }
    }

    private func resolveRetriedConfirmation(
        _ retryConfirmation: PlayerSnapshot,
        intent: PlaybackIntent,
        sourceSnapshot: PlayerSnapshot,
        startedIn generation: UUID
    ) {
        if confirms(intent: intent, with: retryConfirmation) {
            completeConfirmedCommand(
                intent: intent,
                sourceSnapshot: sourceSnapshot,
                confirmation: retryConfirmation,
                startedIn: generation
            )
            return
        }

        if shouldAwaitTrustedPushedStatus(after: retryConfirmation) {
            recordPlaybackAction(
                snapshot: sourceSnapshot,
                intent: intent,
                confirmationOutcome: "transientUntrusted",
                completedAction: nil,
                errorCategory: "transientUntrusted",
                startedIn: generation
            )
            return
        }

        exhaustPendingConfirmation(
            intent: intent,
            sourceSnapshot: sourceSnapshot,
            degradedSnapshot: .playerUnavailable,
            startedIn: generation
        )
    }

    private func exhaustPendingConfirmation(
        intent: PlaybackIntent,
        sourceSnapshot: PlayerSnapshot,
        degradedSnapshot: PlayerSnapshot,
        startedIn generation: UUID
    ) {
        recordPlaybackAction(
            snapshot: sourceSnapshot,
            intent: intent,
            confirmationOutcome: "exhausted",
            completedAction: nil,
            errorCategory: "exhausted",
            startedIn: generation
        )
        resetPolicy()
        suppressCommandsUntilValidSnapshot = true
        updateState(snapshot: degradedSnapshot, isPlayerControllable: false, startedIn: generation)
    }

    private func canStartAttentionSideEffect(startedIn generation: UUID) -> Bool {
        isSameAttentionGeneration(startedIn: generation)
    }

    private func isSameAttentionGeneration(startedIn generation: UUID) -> Bool {
        generation == monitoringGeneration
    }

    private func readSnapshot(startedIn generation: UUID? = nil) async -> PlayerSnapshot? {
        let snapshot = await adapter.snapshot()
        guard isValidOperation(startedIn: generation) else {
            return nil
        }

        playbackMetrics.playbackSnapshots += 1
        return snapshot
    }

    private func isPlayerControllable(_ snapshot: PlayerSnapshot) -> Bool {
        switch snapshot.playbackState {
        case .playing, .paused:
            return snapshot.speed != nil
        case .idle, .setupNeeded, .playerUnavailable, .pluginUpdateRequired:
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

    private func isTransientUntrustedConfirmation(_ snapshot: PlayerSnapshot, for intent: PlaybackIntent) -> Bool {
        switch snapshot.playbackState {
        case .playerUnavailable, .setupNeeded, .pluginUpdateRequired, .idle:
            return true
        case .playing, .paused:
            return snapshot.speed == nil
        }
    }

    private func shouldAwaitTrustedPushedStatus(after snapshot: PlayerSnapshot) -> Bool {
        switch snapshot.playbackState {
        case .playerUnavailable, .setupNeeded, .pluginUpdateRequired, .idle:
            return true
        case .playing, .paused:
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

    private func markNotControllable(snapshot: PlayerSnapshot, startedIn generation: UUID? = nil) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        resetPolicy()
        suppressCommandsUntilValidSnapshot = true
        updateState(snapshot: snapshot, isPlayerControllable: false, startedIn: generation)
    }

    private func resetPolicy() {
        policy = PlaybackPolicy(mode: mode)
        pendingConfirmation = nil
    }

    private func applyReadOnlyPlayerSnapshot(_ snapshot: PlayerSnapshot, startedIn generation: UUID? = nil) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        let isControllable = isPlayerControllable(snapshot)
        if let stoppedReason = state.stoppedReason {
            setState(
                PlaybackCoordinatorState(
                    isPlayerControllable: false,
                    playerSnapshot: snapshot,
                    stoppedReason: stoppedReason
                ),
                startedIn: generation
            )
            return
        }

        if resolvePendingConfirmationFromPushedSnapshotIfNeeded(snapshot, startedIn: generation) {
            return
        }

        if isControllable, applyObservedPlayerSnapshotForManualStopIfNeeded(
            snapshot,
            monitoringActive: monitoringSessionActive,
            startedIn: generation
        ) {
            return
        }

        if isControllable {
            suppressCommandsUntilValidSnapshot = false
        }
        updateState(snapshot: snapshot, isPlayerControllable: isControllable, startedIn: generation)
    }

    @discardableResult
    private func resolvePendingConfirmationFromPushedSnapshotIfNeeded(
        _ snapshot: PlayerSnapshot,
        startedIn generation: UUID? = nil
    ) -> Bool {
        guard let pendingConfirmation else {
            return false
        }

        guard isValidOperation(startedIn: generation),
              pendingConfirmation.generation == monitoringGeneration else {
            return true
        }

        if confirms(intent: pendingConfirmation.intent, with: snapshot) {
            completeConfirmedCommand(
                intent: pendingConfirmation.intent,
                sourceSnapshot: pendingConfirmation.sourceSnapshot,
                confirmation: snapshot,
                startedIn: pendingConfirmation.generation
            )
            return true
        }

        if isTransientUntrustedConfirmation(snapshot, for: pendingConfirmation.intent) {
            return true
        }

        if isPendingCommandEcho(snapshot) {
            updateState(
                snapshot: snapshot,
                isPlayerControllable: isPlayerControllable(snapshot),
                startedIn: generation
            )
            return true
        }

        return false
    }

    private func isPendingCommandEcho(_ snapshot: PlayerSnapshot) -> Bool {
        snapshot.manualAction == nil && isPlayerControllable(snapshot)
    }

    @discardableResult
    private func applyObservedPlayerSnapshotForManualStopIfNeeded(
        _ snapshot: PlayerSnapshot,
        monitoringActive: Bool,
        startedIn generation: UUID? = nil
    ) -> Bool {
        guard isValidOperation(startedIn: generation) else {
            return false
        }

        let result = policy.applyObservedPlayerSnapshot(snapshot, monitoringActive: monitoringActive)
        guard case let .stopMonitoring(reason)? = result.intents.first else {
            return false
        }

        handleStopMonitoring(reason: reason, snapshot: snapshot, startedIn: generation)
        return true
    }

    private func handleStopMonitoring(
        reason: StopMonitoringReason,
        snapshot: PlayerSnapshot,
        startedIn generation: UUID? = nil
    ) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        monitoringSessionActive = false
        resetPolicy()
        setState(
            PlaybackCoordinatorState(
                isPlayerControllable: false,
                playerSnapshot: snapshot,
                stoppedReason: reason
            ),
            startedIn: generation
        )
        emitStopMonitoringRequested(reason, startedIn: generation)
    }

    private func updateState(
        snapshot: PlayerSnapshot,
        isPlayerControllable: Bool,
        startedIn generation: UUID? = nil
    ) {
        setState(
            PlaybackCoordinatorState(
                isPlayerControllable: isPlayerControllable,
                playerSnapshot: snapshot,
                stoppedReason: nil
            ),
            startedIn: generation
        )
    }

    private func setState(_ newState: PlaybackCoordinatorState, startedIn generation: UUID? = nil) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        state = newState
        stateDidChange?(newState)
    }

    private func isValidOperation(startedIn generation: UUID?) -> Bool {
        guard let generation else {
            return true
        }

        return isSameAttentionGeneration(startedIn: generation)
    }

    private func emitStopMonitoringRequested(_ reason: StopMonitoringReason, startedIn generation: UUID?) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        stopMonitoringRequested?(reason)
    }

    private func emitPlaybackActionDidComplete(
        _ completedAction: PlaybackCompletedAction,
        startedIn generation: UUID?
    ) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        playbackActionDidComplete?(completedAction)
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
        case .idle, .setupNeeded, .playerUnavailable, .pluginUpdateRequired:
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
        intent: PlaybackIntent?,
        startedIn generation: UUID? = nil
    ) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

        guard diagnosticMode == .diagnostic, activeDiagnosticSession != nil else {
            return
        }

        let breadcrumb = PlaybackNoOpBreadcrumb(
            attentionState: attentionState.diagnosticName,
            snapshotState: snapshot.playbackState.diagnosticName,
            speedPresent: snapshot.speed != nil,
            intentType: intent?.diagnosticName ?? "none"
        )
        recordPlaybackNoOp(reason: reason, breadcrumb: breadcrumb, startedIn: generation)
    }

    private func recordPlaybackNoOp(
        reason: PlaybackNoOpReason,
        breadcrumb: PlaybackNoOpBreadcrumb,
        startedIn generation: UUID? = nil
    ) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

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
        errorCategory: String,
        startedIn generation: UUID? = nil
    ) {
        guard isValidOperation(startedIn: generation) else {
            return
        }

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

private struct PendingPlaybackConfirmation: Equatable {
    var intent: PlaybackIntent
    var sourceSnapshot: PlayerSnapshot
    var generation: UUID
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
        case .pluginUpdateRequired:
            "pluginUpdateRequired"
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

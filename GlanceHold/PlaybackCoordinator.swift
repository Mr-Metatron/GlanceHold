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
    private var policy: PlaybackPolicy
    private var suppressCommandsUntilValidSnapshot = false
    private var monitoringSessionActive = false

    private(set) var state: PlaybackCoordinatorState {
        didSet {
            stateDidChange?(state)
        }
    }

    var stateDidChange: ((PlaybackCoordinatorState) -> Void)?
    var stopMonitoringRequested: ((StopMonitoringReason) -> Void)?
    var playbackActionDidComplete: ((PlaybackCompletedAction) -> Void)?

    init(mode: MonitoringMode, adapter: IINAPlaybackAdapting) {
        self.mode = mode
        self.adapter = adapter
        self.policy = PlaybackPolicy(mode: mode)
        self.state = .unavailable
    }

    func stopMonitoring() {
        monitoringSessionActive = false
        resetPolicy()
        state = .unavailable
    }

    func refreshPlayerState() async {
        let snapshot = await adapter.snapshot()
        applyReadOnlyPlayerSnapshot(snapshot)
    }

    func applyPushedPlayerSnapshot(_ snapshot: PlayerSnapshot) {
        applyReadOnlyPlayerSnapshot(snapshot)
    }

    func observePlayerStatusUpdates() async {
        for await snapshot in adapter.statusUpdates() {
            if Task.isCancelled {
                return
            }
            applyPushedPlayerSnapshot(snapshot)
        }
    }

    func handleAttentionState(_ state: DebouncedAttentionState) async {
        monitoringSessionActive = true
        let snapshot = await adapter.snapshot()
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

        do {
            try await adapter.execute(intent)
            let confirmation = await adapter.snapshot()
            guard confirms(intent: intent, with: confirmation) else {
                markNotControllable(snapshot: confirmation)
                return
            }

            updateState(snapshot: confirmation, isPlayerControllable: isPlayerControllable(confirmation))
            if let completedAction = completedAction(for: intent) {
                playbackActionDidComplete?(completedAction)
            }
        } catch {
            markNotControllable(snapshot: snapshot)
        }
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
}

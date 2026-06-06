import Foundation

struct PlaybackCoordinatorState: Equatable {
    var isPlayerControllable: Bool
    var playerSnapshot: PlayerSnapshot
    var stoppedReason: StopMonitoringReason?

    static var unavailable: PlaybackCoordinatorState {
        PlaybackCoordinatorState(isPlayerControllable: false, playerSnapshot: .playerUnavailable)
    }
}

final class PlaybackCoordinator {
    private static let speedEpsilon = 0.000_001

    private let mode: MonitoringMode
    private let adapter: IINAPlaybackAdapting
    private var policy: PlaybackPolicy
    private var suppressCommandsUntilValidSnapshot = false

    private(set) var state: PlaybackCoordinatorState {
        didSet {
            stateDidChange?(state)
        }
    }

    var stateDidChange: ((PlaybackCoordinatorState) -> Void)?

    init(mode: MonitoringMode, adapter: IINAPlaybackAdapting) {
        self.mode = mode
        self.adapter = adapter
        self.policy = PlaybackPolicy(mode: mode)
        self.state = .unavailable
    }

    func stopMonitoring() {
        resetPolicy()
        state = .unavailable
    }

    func handleAttentionState(_ state: DebouncedAttentionState) async {
        let snapshot = await adapter.snapshot()
        let isControllable = isPlayerControllable(snapshot)
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
            resetPolicy()
            self.state = PlaybackCoordinatorState(
                isPlayerControllable: false,
                playerSnapshot: snapshot,
                stoppedReason: reason
            )
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
        } catch {
            markNotControllable(snapshot: snapshot)
        }
    }

    private func isPlayerControllable(_ snapshot: PlayerSnapshot) -> Bool {
        switch snapshot.playbackState {
        case .playing, .paused:
            return snapshot.speed != nil
        case .idle, .playerUnavailable:
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

    private func updateState(snapshot: PlayerSnapshot, isPlayerControllable: Bool) {
        state = PlaybackCoordinatorState(
            isPlayerControllable: isPlayerControllable,
            playerSnapshot: snapshot,
            stoppedReason: nil
        )
    }
}

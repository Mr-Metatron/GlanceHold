import Foundation

enum PlayerPlaybackState: Equatable {
    case playing
    case paused
    case idle
    case setupNeeded
    case playerUnavailable
    case pluginUpdateRequired
}

enum PlayerManualAction: Equatable {
    case speedChanged
    case playPressed
    case pausePressed
}

struct PlayerSnapshot: Equatable {
    var playbackState: PlayerPlaybackState
    var speed: Double?
    var manualAction: PlayerManualAction?

    init(playbackState: PlayerPlaybackState, speed: Double?, manualAction: PlayerManualAction? = nil) {
        self.playbackState = playbackState
        self.speed = speed
        self.manualAction = manualAction
    }

    static func playing(speed: Double) -> PlayerSnapshot {
        PlayerSnapshot(playbackState: .playing, speed: speed)
    }

    static func paused(speed: Double) -> PlayerSnapshot {
        PlayerSnapshot(playbackState: .paused, speed: speed)
    }

    static var idle: PlayerSnapshot {
        PlayerSnapshot(playbackState: .idle, speed: nil)
    }

    static var setupNeeded: PlayerSnapshot {
        PlayerSnapshot(playbackState: .setupNeeded, speed: nil)
    }

    static var playerUnavailable: PlayerSnapshot {
        PlayerSnapshot(playbackState: .playerUnavailable, speed: nil)
    }

    static var pluginUpdateRequired: PlayerSnapshot {
        PlayerSnapshot(playbackState: .pluginUpdateRequired, speed: nil)
    }
}

enum StopMonitoringReason: Equatable {
    case manualPlayerTakeover
}

enum PlaybackIntent: Equatable {
    case holdSpeedAtOne
    case restoreSpeed(Double)
    case pause
    case resume
    case stopMonitoring(reason: StopMonitoringReason)
}

enum ManualTakeoverPolicy: Equatable {
    case stopMonitoring
}

struct PlaybackPolicyState: Equatable {
    var mode: MonitoringMode
    var capturedSpeed: Double?
    var pauseOwnedByGlanceHold: Bool
    var stoppedReason: StopMonitoringReason?
    var observedPlayingWhileMonitoringActive: Bool
    var pendingConfirmationIntent: PlaybackIntent?

    init(
        mode: MonitoringMode,
        capturedSpeed: Double? = nil,
        pauseOwnedByGlanceHold: Bool = false,
        stoppedReason: StopMonitoringReason? = nil,
        observedPlayingWhileMonitoringActive: Bool = false,
        pendingConfirmationIntent: PlaybackIntent? = nil
    ) {
        self.mode = mode
        self.capturedSpeed = capturedSpeed
        self.pauseOwnedByGlanceHold = pauseOwnedByGlanceHold
        self.stoppedReason = stoppedReason
        self.observedPlayingWhileMonitoringActive = observedPlayingWhileMonitoringActive
        self.pendingConfirmationIntent = pendingConfirmationIntent
    }
}

struct PlaybackPolicyResult: Equatable {
    var state: PlaybackPolicyState
    var intents: [PlaybackIntent]
}

struct PlaybackPolicy: Equatable {
    private let manualTakeoverPolicy: ManualTakeoverPolicy
    private var state: PlaybackPolicyState

    init(mode: MonitoringMode, manualTakeoverPolicy: ManualTakeoverPolicy = .stopMonitoring) {
        self.manualTakeoverPolicy = manualTakeoverPolicy
        self.state = PlaybackPolicyState(mode: mode)
    }

    @discardableResult
    mutating func beginPendingConfirmation(for intent: PlaybackIntent) -> PlaybackPolicyResult {
        state.pendingConfirmationIntent = intent
        return result([])
    }

    @discardableResult
    mutating func resolvePendingConfirmation(for intent: PlaybackIntent) -> PlaybackPolicyResult {
        if state.pendingConfirmationIntent == intent {
            state.pendingConfirmationIntent = nil
            releaseOwnershipConfirmed(by: intent)
        }
        return result([])
    }

    @discardableResult
    mutating func clearPendingConfirmation() -> PlaybackPolicyResult {
        state.pendingConfirmationIntent = nil
        return result([])
    }

    @discardableResult
    mutating func abandonPendingPauseOwnership() -> PlaybackPolicyResult {
        if state.pendingConfirmationIntent == .pause {
            state.pendingConfirmationIntent = nil
        }
        state.pauseOwnedByGlanceHold = false
        return result([])
    }

    mutating func apply(attention: DebouncedAttentionState, player: PlayerSnapshot) -> PlaybackPolicyResult {
        guard state.stoppedReason == nil else {
            return result([])
        }

        if let takeoverResult = handleExplicitManualActionIfNeeded(player: player) {
            return takeoverResult
        }

        resolvePendingConfirmationIfObserved(player: player)

        if let takeoverResult = handleManualTakeoverIfNeeded(player: player) {
            return takeoverResult
        }

        guard isInterventionEligible(attention: attention, player: player) else {
            return result([])
        }

        switch state.mode {
        case .speedControl:
            return applySpeedControl(attention: attention, player: player)
        case .pauseResume:
            return applyPauseResume(attention: attention, player: player)
        }
    }

    mutating func applyObservedPlayerSnapshot(
        _ player: PlayerSnapshot,
        monitoringActive: Bool
    ) -> PlaybackPolicyResult {
        guard state.stoppedReason == nil else {
            return result([])
        }

        if let takeoverResult = handleExplicitManualActionIfNeeded(player: player) {
            return takeoverResult
        }

        resolvePendingConfirmationIfObserved(player: player)

        if let takeoverResult = handleManualTakeoverIfNeeded(player: player) {
            return takeoverResult
        }

        guard monitoringActive, state.mode == .pauseResume, !state.pauseOwnedByGlanceHold else {
            return result([])
        }

        if player.playbackState == .playing, player.speed != nil {
            state.observedPlayingWhileMonitoringActive = true
            return result([])
        }

        guard state.observedPlayingWhileMonitoringActive else {
            return result([])
        }

        guard player.playbackState == .paused, player.speed != nil else {
            return result([])
        }

        return stopMonitoringForManualTakeover()
    }

    private mutating func applySpeedControl(
        attention: DebouncedAttentionState,
        player: PlayerSnapshot
    ) -> PlaybackPolicyResult {
        switch attention {
        case .lookingAway, .noFaceDetected:
            guard state.pendingConfirmationIntent == nil,
                  state.capturedSpeed == nil,
                  player.playbackState == .playing,
                  let speed = player.speed else {
                return result([])
            }

            state.capturedSpeed = speed
            return result([.holdSpeedAtOne])
        case .facing:
            guard !isPendingRestoreSpeedConfirmation,
                  let capturedSpeed = state.capturedSpeed else {
                return result([])
            }

            return result([.restoreSpeed(capturedSpeed)])
        case .recovering, .unavailable:
            return result([])
        }
    }

    private mutating func applyPauseResume(
        attention: DebouncedAttentionState,
        player: PlayerSnapshot
    ) -> PlaybackPolicyResult {
        switch attention {
        case .lookingAway, .noFaceDetected:
            guard state.pendingConfirmationIntent == nil,
                  !state.pauseOwnedByGlanceHold,
                  player.playbackState == .playing else {
                return result([])
            }

            state.pauseOwnedByGlanceHold = true
            return result([.pause])
        case .facing:
            guard state.pendingConfirmationIntent == nil,
                  state.pauseOwnedByGlanceHold,
                  player.playbackState == .paused else {
                return result([])
            }

            return result([.resume])
        case .recovering, .unavailable:
            return result([])
        }
    }

    private mutating func handleManualTakeoverIfNeeded(player: PlayerSnapshot) -> PlaybackPolicyResult? {
        if state.capturedSpeed != nil || isPendingSpeedConfirmation {
            if player.manualAction == .speedChanged ||
                (!suppressesPendingSpeedEcho(player: player) && observedSpeedWasManuallyChanged(player: player)) {
                return stopMonitoringForManualTakeover()
            }
        }

        if state.pauseOwnedByGlanceHold || isPendingPauseResumeConfirmation {
            if player.manualAction == .playPressed ||
                player.manualAction == .pausePressed ||
                (state.pauseOwnedByGlanceHold &&
                    state.pendingConfirmationIntent == nil &&
                    player.playbackState == .playing &&
                    player.speed != nil) {
                return stopMonitoringForManualTakeover()
            }
        }

        return nil
    }

    private mutating func handleExplicitManualActionIfNeeded(player: PlayerSnapshot) -> PlaybackPolicyResult? {
        guard let manualAction = player.manualAction else {
            return nil
        }

        switch manualAction {
        case .speedChanged where state.capturedSpeed != nil || isPendingSpeedConfirmation:
            return stopMonitoringForManualTakeover()
        case .playPressed, .pausePressed:
            guard state.pauseOwnedByGlanceHold || isPendingPauseResumeConfirmation else {
                return nil
            }

            return stopMonitoringForManualTakeover()
        case .speedChanged:
            return nil
        }
    }

    private func suppressesPendingSpeedEcho(player: PlayerSnapshot) -> Bool {
        guard state.pendingConfirmationIntent == .holdSpeedAtOne,
              player.playbackState == .playing else {
            return false
        }

        return approximatelyEqual(player.speed, 1.0) ||
            (state.capturedSpeed.map { approximatelyEqual(player.speed, $0) } ?? false)
    }

    private var isPendingSpeedConfirmation: Bool {
        switch state.pendingConfirmationIntent {
        case .holdSpeedAtOne, .restoreSpeed:
            true
        case .pause, .resume, .stopMonitoring, nil:
            false
        }
    }

    private var isPendingRestoreSpeedConfirmation: Bool {
        switch state.pendingConfirmationIntent {
        case .restoreSpeed:
            true
        case .holdSpeedAtOne, .pause, .resume, .stopMonitoring, nil:
            false
        }
    }

    private var isPendingPauseResumeConfirmation: Bool {
        switch state.pendingConfirmationIntent {
        case .pause, .resume:
            true
        case .holdSpeedAtOne, .restoreSpeed, .stopMonitoring, nil:
            false
        }
    }

    private mutating func resolvePendingConfirmationIfObserved(player: PlayerSnapshot) {
        guard let pendingIntent = state.pendingConfirmationIntent,
              playerConfirms(intent: pendingIntent, snapshot: player) else {
            return
        }

        resolvePendingConfirmation(for: pendingIntent)
    }

    private mutating func releaseOwnershipConfirmed(by intent: PlaybackIntent) {
        switch intent {
        case .restoreSpeed:
            state.capturedSpeed = nil
        case .resume:
            state.pauseOwnedByGlanceHold = false
        case .holdSpeedAtOne, .pause, .stopMonitoring:
            break
        }
    }

    private func playerConfirms(intent: PlaybackIntent, snapshot: PlayerSnapshot) -> Bool {
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

    private func observedSpeedWasManuallyChanged(player: PlayerSnapshot) -> Bool {
        guard player.playbackState == .playing, let speed = player.speed else {
            return false
        }

        return !approximatelyEqual(speed, 1.0)
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double) -> Bool {
        guard let lhs else {
            return false
        }

        return approximatelyEqual(lhs, rhs)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private mutating func stopMonitoringForManualTakeover() -> PlaybackPolicyResult {
        switch manualTakeoverPolicy {
        case .stopMonitoring:
            state.capturedSpeed = nil
            state.pauseOwnedByGlanceHold = false
            state.stoppedReason = .manualPlayerTakeover
            state.observedPlayingWhileMonitoringActive = false
            state.pendingConfirmationIntent = nil
            return result([.stopMonitoring(reason: .manualPlayerTakeover)])
        }
    }

    private func isInterventionEligible(attention: DebouncedAttentionState, player: PlayerSnapshot) -> Bool {
        switch attention {
        case .recovering, .unavailable:
            return false
        case .facing, .lookingAway, .noFaceDetected:
            break
        }

        switch player.playbackState {
        case .idle, .setupNeeded, .playerUnavailable, .pluginUpdateRequired:
            return false
        case .playing, .paused:
            return player.speed != nil
        }
    }

    private func result(_ intents: [PlaybackIntent]) -> PlaybackPolicyResult {
        PlaybackPolicyResult(state: state, intents: intents)
    }
}

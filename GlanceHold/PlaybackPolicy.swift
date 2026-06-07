import Foundation

enum PlayerPlaybackState: Equatable {
    case playing
    case paused
    case idle
    case setupNeeded
    case playerUnavailable
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

    init(
        mode: MonitoringMode,
        capturedSpeed: Double? = nil,
        pauseOwnedByGlanceHold: Bool = false,
        stoppedReason: StopMonitoringReason? = nil
    ) {
        self.mode = mode
        self.capturedSpeed = capturedSpeed
        self.pauseOwnedByGlanceHold = pauseOwnedByGlanceHold
        self.stoppedReason = stoppedReason
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

    mutating func apply(attention: DebouncedAttentionState, player: PlayerSnapshot) -> PlaybackPolicyResult {
        guard state.stoppedReason == nil else {
            return result([])
        }

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

        if let takeoverResult = handleManualTakeoverIfNeeded(player: player) {
            return takeoverResult
        }

        guard monitoringActive, state.mode == .pauseResume, !state.pauseOwnedByGlanceHold else {
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
            guard state.capturedSpeed == nil, player.playbackState == .playing, let speed = player.speed else {
                return result([])
            }

            state.capturedSpeed = speed
            return result([.holdSpeedAtOne])
        case .facing:
            guard let capturedSpeed = state.capturedSpeed else {
                return result([])
            }

            state.capturedSpeed = nil
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
            guard !state.pauseOwnedByGlanceHold, player.playbackState == .playing else {
                return result([])
            }

            state.pauseOwnedByGlanceHold = true
            return result([.pause])
        case .facing:
            guard state.pauseOwnedByGlanceHold, player.playbackState == .paused else {
                return result([])
            }

            state.pauseOwnedByGlanceHold = false
            return result([.resume])
        case .recovering, .unavailable:
            return result([])
        }
    }

    private mutating func handleManualTakeoverIfNeeded(player: PlayerSnapshot) -> PlaybackPolicyResult? {
        if state.capturedSpeed != nil {
            if player.manualAction == .speedChanged || observedSpeedWasManuallyChanged(player: player) {
                return stopMonitoringForManualTakeover()
            }
        }

        if state.pauseOwnedByGlanceHold {
            if player.manualAction == .playPressed || player.manualAction == .pausePressed || player.playbackState == .playing {
                return stopMonitoringForManualTakeover()
            }
        }

        return nil
    }

    private func observedSpeedWasManuallyChanged(player: PlayerSnapshot) -> Bool {
        guard player.playbackState == .playing, let speed = player.speed else {
            return false
        }

        return abs(speed - 1.0) > 0.000_001
    }

    private mutating func stopMonitoringForManualTakeover() -> PlaybackPolicyResult {
        switch manualTakeoverPolicy {
        case .stopMonitoring:
            state.capturedSpeed = nil
            state.pauseOwnedByGlanceHold = false
            state.stoppedReason = .manualPlayerTakeover
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
        case .idle, .setupNeeded, .playerUnavailable:
            return false
        case .playing, .paused:
            return player.speed != nil
        }
    }

    private func result(_ intents: [PlaybackIntent]) -> PlaybackPolicyResult {
        PlaybackPolicyResult(state: state, intents: intents)
    }
}

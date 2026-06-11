import Foundation

struct AttentionTiming: Equatable {
    var awayDelay: TimeInterval
    var recoveryDelay: TimeInterval

    init(awayDelay: TimeInterval = 1.0, recoveryDelay: TimeInterval = 0.6) {
        self.awayDelay = awayDelay
        self.recoveryDelay = recoveryDelay
    }
}

enum RawAttentionSignal: Equatable {
    case facing
    case away
    case noFace
    case ambiguous
    case unknown
    case uncalibrated
    case cameraPermissionDenied
    case cameraUnavailable
}

struct RawAttentionSample: Equatable {
    var signal: RawAttentionSignal
    var time: TimeInterval
}

enum DebouncedAttentionState: Equatable {
    case facing
    case lookingAway
    case noFaceDetected
    case recovering
    case unavailable
}

enum AttentionTransitionReason: Equatable {
    case stable
    case candidateStarted
    case thresholdPending
    case thresholdReached
    case candidateReset
    case unavailable
}

struct AttentionStateMachineResult: Equatable {
    var rawSignal: RawAttentionSignal
    var previousState: DebouncedAttentionState
    var nextState: DebouncedAttentionState
    var candidateSignal: RawAttentionSignal?
    var candidateStartedAt: TimeInterval?
    var elapsedSinceCandidateStart: TimeInterval?
    var requiredThreshold: TimeInterval?
    var previousEmittedState: DebouncedAttentionState
    var reason: AttentionTransitionReason
}

struct AttentionStateMachine: Equatable {
    private static let thresholdEpsilon: TimeInterval = 0.000_001

    private let timing: AttentionTiming
    private var state: DebouncedAttentionState
    private var candidateSignal: RawAttentionSignal?
    private var candidateStartTime: TimeInterval?
    private var recoveryPausedDuration: TimeInterval
    private var uncertaintyStartTime: TimeInterval?
    private var requiresRecoveryAfterUnavailable: Bool

    init(timing: AttentionTiming = .init()) {
        self.timing = timing
        self.state = .facing
        self.recoveryPausedDuration = 0.0
        self.uncertaintyStartTime = nil
        self.requiresRecoveryAfterUnavailable = false
    }

    mutating func apply(_ sample: RawAttentionSample) -> DebouncedAttentionState {
        applyWithDiagnostics(sample).nextState
    }

    mutating func applyWithDiagnostics(_ sample: RawAttentionSample) -> AttentionStateMachineResult {
        let previousState = state

        switch sample.signal {
        case .facing:
            return applyFacingWithDiagnostics(sample: sample, previousState: previousState)
        case .away:
            return applyAbsenceWithDiagnostics(
                sample: sample,
                previousState: previousState,
                targetState: .lookingAway
            )
        case .noFace:
            return applyAbsenceWithDiagnostics(
                sample: sample,
                previousState: previousState,
                targetState: .noFaceDetected
            )
        case .ambiguous, .unknown:
            return applyUncertaintyWithDiagnostics(sample: sample, previousState: previousState)
        case .uncalibrated, .cameraPermissionDenied, .cameraUnavailable:
            resetCandidate()
            uncertaintyStartTime = nil
            requiresRecoveryAfterUnavailable = false
            state = .unavailable
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: nil,
                requiredThreshold: nil,
                reason: .unavailable
            )
        }
    }

    private mutating func applyFacingWithDiagnostics(
        sample: RawAttentionSample,
        previousState: DebouncedAttentionState
    ) -> AttentionStateMachineResult {
        finishUncertaintyPauseIfNeeded(at: sample.time)

        switch state {
        case .lookingAway, .noFaceDetected, .recovering:
            return applyRecoveryCandidateWithDiagnostics(sample: sample, previousState: previousState)
        case .unavailable where requiresRecoveryAfterUnavailable:
            return applyRecoveryCandidateWithDiagnostics(sample: sample, previousState: previousState)
        case .facing, .unavailable:
            let hadCandidate = candidateSignal != nil
            resetCandidate()
            requiresRecoveryAfterUnavailable = false
            state = .facing
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: nil,
                requiredThreshold: nil,
                reason: hadCandidate ? .candidateReset : .stable
            )
        }
    }

    private mutating func applyRecoveryCandidateWithDiagnostics(
        sample: RawAttentionSample,
        previousState: DebouncedAttentionState
    ) -> AttentionStateMachineResult {
        if candidateSignal != .facing {
            candidateSignal = .facing
            candidateStartTime = sample.time
            recoveryPausedDuration = 0.0
            state = .recovering
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: 0.0,
                requiredThreshold: timing.recoveryDelay,
                reason: .candidateStarted
            )
        }

        let elapsed = recoveryElapsed(at: sample.time) ?? 0.0
        if hasReachedThreshold(elapsed: elapsed, threshold: timing.recoveryDelay) {
            resetCandidate()
            requiresRecoveryAfterUnavailable = false
            state = .facing
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: elapsed,
                requiredThreshold: timing.recoveryDelay,
                reason: .thresholdReached
            )
        } else {
            state = .recovering
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: elapsed,
                requiredThreshold: timing.recoveryDelay,
                reason: .thresholdPending
            )
        }
    }

    private mutating func applyAbsenceWithDiagnostics(
        sample: RawAttentionSample,
        previousState: DebouncedAttentionState,
        targetState: DebouncedAttentionState
    ) -> AttentionStateMachineResult {
        uncertaintyStartTime = nil

        if state == targetState {
            resetCandidate()
            requiresRecoveryAfterUnavailable = false
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: nil,
                requiredThreshold: nil,
                reason: .stable
            )
        }

        if candidateSignal != sample.signal {
            let reason: AttentionTransitionReason = candidateSignal == nil ? .candidateStarted : .candidateReset
            candidateSignal = sample.signal
            candidateStartTime = sample.time
            recoveryPausedDuration = 0.0
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: 0.0,
                requiredThreshold: timing.awayDelay,
                reason: reason
            )
        }

        let startedAt = candidateStartTime ?? sample.time
        let elapsed = sample.time - startedAt
        if hasReachedThreshold(from: startedAt, to: sample.time, threshold: timing.awayDelay) {
            resetCandidate()
            requiresRecoveryAfterUnavailable = false
            state = targetState
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: elapsed,
                requiredThreshold: timing.awayDelay,
                reason: .thresholdReached
            )
        }

        return result(
            sample: sample,
            previousState: previousState,
            elapsed: elapsed,
            requiredThreshold: timing.awayDelay,
            reason: .thresholdPending
        )
    }

    private mutating func applyUncertaintyWithDiagnostics(
        sample: RawAttentionSample,
        previousState: DebouncedAttentionState
    ) -> AttentionStateMachineResult {
        guard state != .unavailable else {
            resetCandidate()
            uncertaintyStartTime = nil
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: nil,
                requiredThreshold: nil,
                reason: .unavailable
            )
        }

        if state != .recovering {
            resetCandidate()
        }

        if uncertaintyStartTime == nil {
            uncertaintyStartTime = sample.time
        }

        let startedAt = uncertaintyStartTime ?? sample.time
        let uncertaintyElapsed = sample.time - startedAt
        if hasReachedThreshold(from: startedAt, to: sample.time, threshold: timing.recoveryDelay) {
            resetCandidate()
            uncertaintyStartTime = nil
            state = .unavailable
            requiresRecoveryAfterUnavailable = true
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: uncertaintyElapsed,
                requiredThreshold: timing.recoveryDelay,
                reason: .unavailable
            )
        }

        let elapsed = state == .recovering ? recoveryElapsed(at: sample.time) : uncertaintyElapsed
        return result(
            sample: sample,
            previousState: previousState,
            elapsed: elapsed,
            requiredThreshold: timing.recoveryDelay,
            reason: .thresholdPending
        )
    }

    private mutating func finishUncertaintyPauseIfNeeded(at time: TimeInterval) {
        guard let uncertaintyStartTime else {
            return
        }

        if state == .recovering, candidateSignal == .facing {
            recoveryPausedDuration += max(0.0, time - uncertaintyStartTime)
        }
        self.uncertaintyStartTime = nil
    }

    private func recoveryElapsed(at time: TimeInterval) -> TimeInterval? {
        guard candidateSignal == .facing, let candidateStartTime else {
            return nil
        }

        let currentPauseDuration: TimeInterval
        if let uncertaintyStartTime {
            currentPauseDuration = max(0.0, time - uncertaintyStartTime)
        } else {
            currentPauseDuration = 0.0
        }

        return max(0.0, time - candidateStartTime - recoveryPausedDuration - currentPauseDuration)
    }

    private mutating func resetCandidate() {
        candidateSignal = nil
        candidateStartTime = nil
        recoveryPausedDuration = 0.0
    }

    private func hasReachedThreshold(from startTime: TimeInterval, to time: TimeInterval, threshold: TimeInterval) -> Bool {
        time - startTime + Self.thresholdEpsilon >= threshold
    }

    private func hasReachedThreshold(elapsed: TimeInterval, threshold: TimeInterval) -> Bool {
        elapsed + Self.thresholdEpsilon >= threshold
    }

    private func result(
        sample: RawAttentionSample,
        previousState: DebouncedAttentionState,
        elapsed: TimeInterval?,
        requiredThreshold: TimeInterval?,
        reason: AttentionTransitionReason
    ) -> AttentionStateMachineResult {
        AttentionStateMachineResult(
            rawSignal: sample.signal,
            previousState: previousState,
            nextState: state,
            candidateSignal: candidateSignal,
            candidateStartedAt: candidateStartTime,
            elapsedSinceCandidateStart: elapsed,
            requiredThreshold: requiredThreshold,
            previousEmittedState: previousState,
            reason: reason
        )
    }
}

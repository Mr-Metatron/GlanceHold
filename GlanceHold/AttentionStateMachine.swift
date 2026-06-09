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

    init(timing: AttentionTiming = .init()) {
        self.timing = timing
        self.state = .facing
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
        case .ambiguous, .unknown, .uncalibrated, .cameraPermissionDenied, .cameraUnavailable:
            candidateSignal = nil
            candidateStartTime = nil
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
        switch state {
        case .lookingAway, .noFaceDetected, .recovering:
            return applyRecoveryCandidateWithDiagnostics(sample: sample, previousState: previousState)
        case .facing, .unavailable:
            let hadCandidate = candidateSignal != nil
            candidateSignal = nil
            candidateStartTime = nil
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
            state = .recovering
            return result(
                sample: sample,
                previousState: previousState,
                elapsed: 0.0,
                requiredThreshold: timing.recoveryDelay,
                reason: .candidateStarted
            )
        }

        let startedAt = candidateStartTime ?? sample.time
        let elapsed = sample.time - startedAt
        if hasReachedThreshold(from: startedAt, to: sample.time, threshold: timing.recoveryDelay) {
            candidateSignal = nil
            candidateStartTime = nil
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
        if state == targetState {
            candidateSignal = nil
            candidateStartTime = nil
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
            candidateSignal = nil
            candidateStartTime = nil
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

    private func hasReachedThreshold(from startTime: TimeInterval, to time: TimeInterval, threshold: TimeInterval) -> Bool {
        time - startTime + Self.thresholdEpsilon >= threshold
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

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
        switch sample.signal {
        case .facing:
            return applyFacing(at: sample.time)
        case .away:
            return applyAbsence(signal: .away, at: sample.time, targetState: .lookingAway)
        case .noFace:
            return applyAbsence(signal: .noFace, at: sample.time, targetState: .noFaceDetected)
        case .ambiguous, .unknown, .uncalibrated, .cameraPermissionDenied, .cameraUnavailable:
            candidateSignal = nil
            candidateStartTime = nil
            state = .unavailable
            return state
        }
    }

    private mutating func applyFacing(at time: TimeInterval) -> DebouncedAttentionState {
        switch state {
        case .lookingAway, .noFaceDetected, .recovering:
            return applyRecoveryCandidate(at: time)
        case .facing, .unavailable:
            candidateSignal = nil
            candidateStartTime = nil
            state = .facing
            return state
        }
    }

    private mutating func applyRecoveryCandidate(at time: TimeInterval) -> DebouncedAttentionState {
        if candidateSignal != .facing {
            candidateSignal = .facing
            candidateStartTime = time
            state = .recovering
            return state
        }

        let startedAt = candidateStartTime ?? time
        if hasReachedThreshold(from: startedAt, to: time, threshold: timing.recoveryDelay) {
            candidateSignal = nil
            candidateStartTime = nil
            state = .facing
        } else {
            state = .recovering
        }

        return state
    }

    private mutating func applyAbsence(
        signal: RawAttentionSignal,
        at time: TimeInterval,
        targetState: DebouncedAttentionState
    ) -> DebouncedAttentionState {
        if state == targetState {
            candidateSignal = nil
            candidateStartTime = nil
            return state
        }

        if candidateSignal != signal {
            candidateSignal = signal
            candidateStartTime = time
            return state
        }

        let startedAt = candidateStartTime ?? time
        if hasReachedThreshold(from: startedAt, to: time, threshold: timing.awayDelay) {
            candidateSignal = nil
            candidateStartTime = nil
            state = targetState
        }

        return state
    }

    private func hasReachedThreshold(from startTime: TimeInterval, to time: TimeInterval, threshold: TimeInterval) -> Bool {
        time - startTime + Self.thresholdEpsilon >= threshold
    }
}

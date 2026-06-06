import Foundation

struct PoseSample: Equatable, Codable {
    var yawDegrees: Double
    var pitchDegrees: Double
    var rollDegrees: Double
    var time: TimeInterval
}

enum CalibrationQuality: Equatable, Codable {
    case high
    case marginal
    case failed
}

struct CalibrationSnapshot: Equatable, Codable {
    var neutralPose: PoseSample
    var quality: CalibrationQuality
    var createdAt: Date
}

enum CalibrationResult: Equatable {
    case accepted(CalibrationSnapshot)
    case needsReplacementConfirmation(candidate: CalibrationSnapshot, existing: CalibrationSnapshot)
    case failed(previous: CalibrationSnapshot?)
}

enum CalibrationReplacementDecision: Equatable {
    case keepCurrent
    case useNew
}

enum CalibratedAttentionInput: Equatable {
    case pose(PoseSample)
    case noFace
    case ambiguous
    case unknown
}

enum CalibrationModel {
    private static let minimumSampleCount = 3
    private static let highSpreadThresholdDegrees = 1.0
    private static let marginalSpreadThresholdDegrees = 3.0

    static func evaluate(
        samples: [PoseSample],
        existing: CalibrationSnapshot?,
        createdAt: Date = Date()
    ) -> CalibrationResult {
        guard samples.count >= minimumSampleCount else {
            return .failed(previous: existing)
        }

        let yaw = average(samples.map(\.yawDegrees))
        let pitch = average(samples.map(\.pitchDegrees))
        let roll = average(samples.map(\.rollDegrees))
        let spread = maxSpread(samples)

        let quality: CalibrationQuality
        if spread <= highSpreadThresholdDegrees {
            quality = .high
        } else if spread <= marginalSpreadThresholdDegrees {
            quality = .marginal
        } else {
            return .failed(previous: existing)
        }

        let candidate = CalibrationSnapshot(
            neutralPose: PoseSample(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll, time: samples.last?.time ?? 0.0),
            quality: quality,
            createdAt: createdAt
        )

        if quality == .marginal, existing?.quality == .high {
            return .needsReplacementConfirmation(candidate: candidate, existing: existing!)
        }

        return .accepted(candidate)
    }

    static func resolveReplacement(
        candidate: CalibrationSnapshot,
        existing: CalibrationSnapshot,
        decision: CalibrationReplacementDecision
    ) -> CalibrationSnapshot {
        switch decision {
        case .keepCurrent:
            existing
        case .useNew:
            candidate
        }
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0.0, +) / Double(values.count)
    }

    private static func maxSpread(_ samples: [PoseSample]) -> Double {
        [
            spread(samples.map(\.yawDegrees)),
            spread(samples.map(\.pitchDegrees)),
            spread(samples.map(\.rollDegrees))
        ].max() ?? .infinity
    }

    private static func spread(_ values: [Double]) -> Double {
        guard let min = values.min(), let max = values.max() else {
            return .infinity
        }

        return max - min
    }
}

struct CalibratedAttentionClassifier: Equatable {
    var settings: AttentionSettings

    func classify(_ input: CalibratedAttentionInput) -> RawAttentionSignal {
        switch input {
        case .pose(let pose):
            guard let calibration = settings.calibration else {
                return .uncalibrated
            }

            let yawDelta = abs(pose.yawDegrees - calibration.neutralPose.yawDegrees)
            let pitchDelta = abs(pose.pitchDegrees - calibration.neutralPose.pitchDegrees)

            if yawDelta > settings.headTurnThresholdDegrees || pitchDelta > settings.headTurnThresholdDegrees {
                return .away
            }

            return .facing
        case .noFace:
            return .noFace
        case .ambiguous:
            return .ambiguous
        case .unknown:
            return .unknown
        }
    }
}

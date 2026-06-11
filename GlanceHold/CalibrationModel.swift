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

enum CalibrationFailureReason: String, Equatable {
    case notEnoughPoseSamples
    case stableWindowTooShort
    case unstablePoseSpread
}

struct CalibrationEvaluationDiagnostics: Equatable {
    var inputSampleCount: Int
    var selectedWindowSampleCount: Int
    var selectedWindowDurationSeconds: TimeInterval?
    var selectedWindowSpreadDegrees: Double?
    var selectedWindowQuality: CalibrationQuality?
    var failureReason: CalibrationFailureReason?
}

struct CalibrationEvaluation: Equatable {
    var result: CalibrationResult
    var diagnostics: CalibrationEvaluationDiagnostics
}

enum CalibratedAttentionInput: Equatable {
    case pose(PoseSample)
    case noFace
    case ambiguous
    case unknown
}

enum CalibrationModel {
    private static let minimumSampleCount = 5
    private static let minimumWindowDurationSeconds = 1.0
    private static let highSpreadThresholdDegrees = 1.0
    private static let marginalSpreadThresholdDegrees = 3.0

    static func evaluate(
        samples: [PoseSample],
        existing: CalibrationSnapshot?,
        createdAt: Date = Date()
    ) -> CalibrationResult {
        evaluateDetailed(samples: samples, existing: existing, createdAt: createdAt).result
    }

    static func evaluateDetailed(
        samples: [PoseSample],
        existing: CalibrationSnapshot?,
        createdAt: Date = Date()
    ) -> CalibrationEvaluation {
        guard samples.count >= minimumSampleCount else {
            return CalibrationEvaluation(
                result: .failed(previous: existing),
                diagnostics: CalibrationEvaluationDiagnostics(
                    inputSampleCount: samples.count,
                    selectedWindowSampleCount: 0,
                    selectedWindowDurationSeconds: nil,
                    selectedWindowSpreadDegrees: nil,
                    selectedWindowQuality: nil,
                    failureReason: .notEnoughPoseSamples
                )
            )
        }

        let orderedSamples = samples.sorted { $0.time < $1.time }
        guard let selectedWindow = bestWindow(in: orderedSamples) else {
            return CalibrationEvaluation(
                result: .failed(previous: existing),
                diagnostics: CalibrationEvaluationDiagnostics(
                    inputSampleCount: samples.count,
                    selectedWindowSampleCount: 0,
                    selectedWindowDurationSeconds: nil,
                    selectedWindowSpreadDegrees: nil,
                    selectedWindowQuality: nil,
                    failureReason: .stableWindowTooShort
                )
            )
        }

        guard let quality = quality(forSpread: selectedWindow.spreadDegrees) else {
            return CalibrationEvaluation(
                result: .failed(previous: existing),
                diagnostics: CalibrationEvaluationDiagnostics(
                    inputSampleCount: samples.count,
                    selectedWindowSampleCount: selectedWindow.samples.count,
                    selectedWindowDurationSeconds: duration(of: selectedWindow.samples),
                    selectedWindowSpreadDegrees: selectedWindow.spreadDegrees,
                    selectedWindowQuality: nil,
                    failureReason: .unstablePoseSpread
                )
            )
        }

        let candidate = CalibrationSnapshot(
            neutralPose: neutralPose(from: selectedWindow.samples),
            quality: quality,
            createdAt: createdAt
        )

        let result: CalibrationResult
        if quality == .marginal, existing?.quality == .high {
            result = .needsReplacementConfirmation(candidate: candidate, existing: existing!)
        } else {
            result = .accepted(candidate)
        }

        return CalibrationEvaluation(
            result: result,
            diagnostics: CalibrationEvaluationDiagnostics(
                inputSampleCount: samples.count,
                selectedWindowSampleCount: selectedWindow.samples.count,
                selectedWindowDurationSeconds: duration(of: selectedWindow.samples),
                selectedWindowSpreadDegrees: selectedWindow.spreadDegrees,
                selectedWindowQuality: quality,
                failureReason: nil
            )
        )
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

    private struct CalibrationWindow {
        var samples: [PoseSample]
        var spreadDegrees: Double
    }

    private static func bestWindow(in samples: [PoseSample]) -> CalibrationWindow? {
        guard samples.count >= minimumSampleCount else {
            return nil
        }

        var best: CalibrationWindow?

        for start in 0...(samples.count - minimumSampleCount) {
            for length in minimumSampleCount...(samples.count - start) {
                let windowSamples = Array(samples[start..<(start + length)])
                guard isValidWindow(windowSamples) else {
                    continue
                }

                let window = CalibrationWindow(
                    samples: windowSamples,
                    spreadDegrees: maxSpread(windowSamples)
                )

                guard let currentBest = best else {
                    best = window
                    continue
                }

                if window.spreadDegrees < currentBest.spreadDegrees ||
                    (window.spreadDegrees == currentBest.spreadDegrees && window.samples.count > currentBest.samples.count) {
                    best = window
                }
            }
        }

        return best
    }

    private static func isValidWindow(_ samples: [PoseSample]) -> Bool {
        guard samples.count >= minimumSampleCount,
              let duration = duration(of: samples) else {
            return false
        }

        return duration >= minimumWindowDurationSeconds
    }

    private static func quality(forSpread spread: Double) -> CalibrationQuality? {
        if spread <= highSpreadThresholdDegrees {
            return .high
        }

        if spread <= marginalSpreadThresholdDegrees {
            return .marginal
        }

        return nil
    }

    private static func neutralPose(from samples: [PoseSample]) -> PoseSample {
        PoseSample(
            yawDegrees: average(samples.map(\.yawDegrees)),
            pitchDegrees: average(samples.map(\.pitchDegrees)),
            rollDegrees: average(samples.map(\.rollDegrees)),
            time: samples.last?.time ?? 0.0
        )
    }

    private static func duration(of samples: [PoseSample]) -> TimeInterval? {
        guard let first = samples.first?.time, let last = samples.last?.time else {
            return nil
        }

        return max(last - first, 0.0)
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

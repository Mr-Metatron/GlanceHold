import Foundation

enum AttentionSensitivity: String, CaseIterable, Equatable, Codable {
    case relaxed
    case balanced
    case strict

    var displayName: String {
        switch self {
        case .relaxed:
            "Relaxed"
        case .balanced:
            "Balanced"
        case .strict:
            "Strict"
        }
    }

    var thresholdDegrees: Double {
        switch self {
        case .relaxed:
            24.0
        case .balanced:
            18.0
        case .strict:
            12.0
        }
    }
}

struct AttentionSettings: Equatable, Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: MonitoringMode
    var sensitivity: AttentionSensitivity
    var headTurnThresholdDegrees: Double
    var speedControlAwayDelay: TimeInterval
    var pauseResumeAwayDelay: TimeInterval
    var recoveryDelay: TimeInterval
    var calibration: CalibrationSnapshot?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        mode: MonitoringMode = .speedControl,
        sensitivity: AttentionSensitivity = .balanced,
        headTurnThresholdDegrees: Double = 18.0,
        speedControlAwayDelay: TimeInterval = 0.8,
        pauseResumeAwayDelay: TimeInterval = 1.2,
        recoveryDelay: TimeInterval = 0.6,
        calibration: CalibrationSnapshot? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.sensitivity = sensitivity
        self.headTurnThresholdDegrees = headTurnThresholdDegrees
        self.speedControlAwayDelay = speedControlAwayDelay
        self.pauseResumeAwayDelay = pauseResumeAwayDelay
        self.recoveryDelay = recoveryDelay
        self.calibration = calibration
    }

    static let defaults = AttentionSettings()

    func timing(for mode: MonitoringMode) -> AttentionTiming {
        switch mode {
        case .speedControl:
            AttentionTiming(awayDelay: speedControlAwayDelay, recoveryDelay: recoveryDelay)
        case .pauseResume:
            AttentionTiming(awayDelay: pauseResumeAwayDelay, recoveryDelay: recoveryDelay)
        }
    }

    func withCalibration(_ calibration: CalibrationSnapshot?) -> AttentionSettings {
        var copy = self
        copy.calibration = calibration
        return copy
    }

    func withSensitivity(_ sensitivity: AttentionSensitivity) -> AttentionSettings {
        var copy = self
        copy.sensitivity = sensitivity
        copy.headTurnThresholdDegrees = sensitivity.thresholdDegrees
        return copy
    }
}

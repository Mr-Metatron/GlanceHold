import Foundation

protocol AttentionSettingsStoring {
    func load() -> AttentionSettings
    func save(_ settings: AttentionSettings) throws
    func reset() throws
}

struct UserDefaultsAttentionSettingsStore: AttentionSettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        key: String = "com.metatron.GlanceHold.attentionSettings.v1",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = UserDefaultsAttentionSettingsStore.makeDecoder()
    ) {
        self.defaults = defaults
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> AttentionSettings {
        guard
            let data = defaults.data(forKey: key),
            let persistedSettings = try? decoder.decode(PersistedAttentionSettings.self, from: data),
            persistedSettings.schemaVersion == AttentionSettings.currentSchemaVersion
        else {
            return .defaults
        }

        let repair = AttentionSettingsLoadRepair.repair(persistedSettings)
        if repair.didRepair {
            try? save(repair.settings)
        }

        return repair.settings
    }

    func save(_ settings: AttentionSettings) throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }

    func reset() throws {
        defaults.removeObject(forKey: key)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}

private struct PersistedAttentionSettings: Decodable {
    var schemaVersion: Int?
    var modeRawValue: String?
    var sensitivityRawValue: String?
    var headTurnThresholdDegrees: Double?
    var speedControlAwayDelay: TimeInterval?
    var pauseResumeAwayDelay: TimeInterval?
    var recoveryDelay: TimeInterval?
    var calibration: CalibrationSnapshot?
    var hasCalibrationField: Bool

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case sensitivity
        case headTurnThresholdDegrees
        case speedControlAwayDelay
        case pauseResumeAwayDelay
        case recoveryDelay
        case calibration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try? container.decode(Int.self, forKey: .schemaVersion)
        modeRawValue = try? container.decode(String.self, forKey: .mode)
        sensitivityRawValue = try? container.decode(String.self, forKey: .sensitivity)
        headTurnThresholdDegrees = try? container.decode(Double.self, forKey: .headTurnThresholdDegrees)
        speedControlAwayDelay = try? container.decode(TimeInterval.self, forKey: .speedControlAwayDelay)
        pauseResumeAwayDelay = try? container.decode(TimeInterval.self, forKey: .pauseResumeAwayDelay)
        recoveryDelay = try? container.decode(TimeInterval.self, forKey: .recoveryDelay)
        hasCalibrationField = container.contains(.calibration)
        calibration = try? container.decodeIfPresent(CalibrationSnapshot.self, forKey: .calibration)
    }
}

private struct AttentionSettingsLoadRepair {
    var settings: AttentionSettings
    var didRepair: Bool

    static func repair(_ persistedSettings: PersistedAttentionSettings) -> AttentionSettingsLoadRepair {
        var didRepair = false
        let defaults = AttentionSettings.defaults
        let mode = repairedMode(persistedSettings.modeRawValue, didRepair: &didRepair)
        let sensitivityRepair = repairedSensitivity(persistedSettings.sensitivityRawValue)
        didRepair = didRepair || sensitivityRepair.didRepair
        let thresholdDefault = sensitivityRepair.didRepair
            ? defaults.headTurnThresholdDegrees
            : sensitivityRepair.sensitivity.thresholdDegrees

        let headTurnThresholdDegrees = repairedNumber(
            persistedSettings.headTurnThresholdDegrees,
            bounds: AttentionSettings.headTurnThresholdBounds,
            defaultValue: thresholdDefault,
            didRepair: &didRepair
        )
        let speedControlAwayDelay = repairedNumber(
            persistedSettings.speedControlAwayDelay,
            bounds: AttentionSettings.delayBounds,
            defaultValue: defaults.speedControlAwayDelay,
            didRepair: &didRepair
        )
        let pauseResumeAwayDelay = repairedNumber(
            persistedSettings.pauseResumeAwayDelay,
            bounds: AttentionSettings.delayBounds,
            defaultValue: defaults.pauseResumeAwayDelay,
            didRepair: &didRepair
        )
        let recoveryDelay = repairedNumber(
            persistedSettings.recoveryDelay,
            bounds: AttentionSettings.delayBounds,
            defaultValue: defaults.recoveryDelay,
            didRepair: &didRepair
        )
        let calibration = repairedCalibration(
            persistedSettings.calibration,
            hasCalibrationField: persistedSettings.hasCalibrationField,
            didRepair: &didRepair
        )

        let settings = AttentionSettings(
            schemaVersion: AttentionSettings.currentSchemaVersion,
            mode: mode,
            sensitivity: sensitivityRepair.sensitivity,
            headTurnThresholdDegrees: headTurnThresholdDegrees,
            speedControlAwayDelay: speedControlAwayDelay,
            pauseResumeAwayDelay: pauseResumeAwayDelay,
            recoveryDelay: recoveryDelay,
            calibration: calibration
        )

        return AttentionSettingsLoadRepair(settings: settings, didRepair: didRepair)
    }

    private static func repairedMode(
        _ rawValue: String?,
        didRepair: inout Bool
    ) -> MonitoringMode {
        guard let rawValue, let mode = MonitoringMode(rawValue: rawValue) else {
            didRepair = true
            return AttentionSettings.defaults.mode
        }

        return mode
    }

    private static func repairedSensitivity(
        _ rawValue: String?
    ) -> (sensitivity: AttentionSensitivity, didRepair: Bool) {
        guard let rawValue, let sensitivity = AttentionSensitivity(rawValue: rawValue) else {
            return (AttentionSettings.defaults.sensitivity, true)
        }

        return (sensitivity, false)
    }

    private static func repairedNumber(
        _ value: Double?,
        bounds: ClosedRange<Double>,
        defaultValue: Double,
        didRepair: inout Bool
    ) -> Double {
        guard let value else {
            didRepair = true
            return defaultValue
        }

        guard value.isFinite else {
            didRepair = true
            return defaultValue
        }

        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        if clampedValue != value {
            didRepair = true
        }

        return clampedValue
    }

    private static func repairedCalibration(
        _ calibration: CalibrationSnapshot?,
        hasCalibrationField: Bool,
        didRepair: inout Bool
    ) -> CalibrationSnapshot? {
        guard let calibration else {
            if hasCalibrationField {
                didRepair = true
            }
            return nil
        }

        guard calibration.neutralPose.yawDegrees.isFinite,
              calibration.neutralPose.pitchDegrees.isFinite,
              calibration.neutralPose.rollDegrees.isFinite,
              calibration.neutralPose.time.isFinite,
              calibration.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            didRepair = true
            return nil
        }

        return calibration
    }
}

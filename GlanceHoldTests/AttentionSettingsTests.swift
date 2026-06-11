import XCTest
@testable import GlanceHold

final class AttentionSettingsTests: XCTestCase {
    func testDefaultSettingsUseSpeedControlBalancedAndModeSpecificTiming() {
        let settings = AttentionSettings.defaults

        XCTAssertEqual(settings.schemaVersion, 1)
        XCTAssertEqual(settings.mode, .speedControl)
        XCTAssertEqual(settings.sensitivity, .balanced)
        XCTAssertEqual(settings.headTurnThresholdDegrees, 18.0)
        XCTAssertEqual(settings.speedControlAwayDelay, 0.8)
        XCTAssertEqual(settings.pauseResumeAwayDelay, 1.2)
        XCTAssertEqual(settings.recoveryDelay, 0.6)
        XCTAssertLessThan(settings.speedControlAwayDelay, settings.pauseResumeAwayDelay)
        XCTAssertNil(settings.calibration)

        XCTAssertEqual(settings.timing(for: .speedControl), AttentionTiming(awayDelay: 0.8, recoveryDelay: 0.6))
        XCTAssertEqual(settings.timing(for: .pauseResume), AttentionTiming(awayDelay: 1.2, recoveryDelay: 0.6))
    }

    func testSensitivityPresetsIncludeRelaxedBalancedAndStrict() {
        XCTAssertEqual(AttentionSensitivity.allCases, [.relaxed, .balanced, .strict])
        XCTAssertGreaterThan(AttentionSensitivity.relaxed.thresholdDegrees, AttentionSensitivity.balanced.thresholdDegrees)
        XCTAssertLessThan(AttentionSensitivity.strict.thresholdDegrees, AttentionSensitivity.balanced.thresholdDegrees)
    }

    func testMenuFacingTuningLabelsAndSensitivityNamesAreStable() {
        XCTAssertEqual(AttentionSensitivity.allCases.map(\.displayName), [
            GlanceHoldStrings.text(.sensitivityRelaxed),
            GlanceHoldStrings.text(.sensitivityBalanced),
            GlanceHoldStrings.text(.sensitivityStrict)
        ])
        XCTAssertEqual(GlanceHoldMenuCopy.sensitivityLabel, GlanceHoldStrings.text(.tuningSensitivity))
        XCTAssertEqual(GlanceHoldMenuCopy.speedControlAwayDelayLabel, GlanceHoldStrings.text(.tuningSpeedControlAwayDelay))
        XCTAssertEqual(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel, GlanceHoldStrings.text(.tuningPauseResumeAwayDelay))
        XCTAssertEqual(GlanceHoldMenuCopy.recoveryDelayLabel, GlanceHoldStrings.text(.tuningRecoveryDelay))
    }

    func testCompactDelayLabelsUseOneDecimalSecondSuffix() {
        XCTAssertEqual(TuningMenuPresentation.formatDelay(0.8), GlanceHoldStrings.delaySeconds(0.8))
        XCTAssertEqual(TuningMenuPresentation.formatDelay(1.2), GlanceHoldStrings.delaySeconds(1.2))
    }

    func testStoreRoundTripsScalarSettingsAndResetClearsCalibration() throws {
        let store = InMemoryAttentionSettingsStore()
        let calibration = CalibrationSnapshot(
            neutralPose: PoseSample(yawDegrees: 1.0, pitchDegrees: 2.0, rollDegrees: 3.0, time: 4.0),
            quality: .marginal,
            createdAt: Date(timeIntervalSince1970: 5.0)
        )
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .strict,
            headTurnThresholdDegrees: 12.0,
            speedControlAwayDelay: 0.7,
            pauseResumeAwayDelay: 1.5,
            recoveryDelay: 0.9,
            calibration: calibration
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)

        try store.reset()

        let resetSettings = store.load()
        XCTAssertNil(resetSettings.calibration)
        XCTAssertEqual(resetSettings, .defaults)
    }

    func testUserDefaultsLoadClampsFiniteOutOfRangeNumericsAndWritesBack() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.finite.\(UUID().uuidString)"
        let calibration = calibrationSnapshot()
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .strict,
            headTurnThresholdDegrees: 18.0,
            speedControlAwayDelay: 0.8,
            pauseResumeAwayDelay: 1.2,
            recoveryDelay: 0.6,
            calibration: calibration
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object["headTurnThresholdDegrees"] = 99.0
            object["speedControlAwayDelay"] = -4.0
            object["pauseResumeAwayDelay"] = 0.0
            object["recoveryDelay"] = 999.0
        }

        let repaired = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(repaired.mode, .pauseResume)
        XCTAssertEqual(repaired.sensitivity, .strict)
        XCTAssertEqual(repaired.headTurnThresholdDegrees, 24.0)
        XCTAssertEqual(repaired.speedControlAwayDelay, 0.5)
        XCTAssertEqual(repaired.pauseResumeAwayDelay, 0.5)
        XCTAssertEqual(repaired.recoveryDelay, 2.0)
        XCTAssertEqual(repaired.calibration, calibration)
        XCTAssertEqual(UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load(), repaired)
    }

    func testUserDefaultsLoadMigratesLegacyPayloadWithoutSchemaVersionAndWritesBack() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.legacy.\(UUID().uuidString)"
        let calibration = calibrationSnapshot()
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .strict,
            headTurnThresholdDegrees: 12.0,
            speedControlAwayDelay: 0.7,
            pauseResumeAwayDelay: 1.5,
            recoveryDelay: 0.9,
            calibration: calibration
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object.removeValue(forKey: "schemaVersion")
        }

        let migrated = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(migrated.schemaVersion, AttentionSettings.currentSchemaVersion)
        XCTAssertEqual(migrated.mode, settings.mode)
        XCTAssertEqual(migrated.sensitivity, settings.sensitivity)
        XCTAssertEqual(migrated.headTurnThresholdDegrees, settings.headTurnThresholdDegrees)
        XCTAssertEqual(migrated.speedControlAwayDelay, settings.speedControlAwayDelay)
        XCTAssertEqual(migrated.pauseResumeAwayDelay, settings.pauseResumeAwayDelay)
        XCTAssertEqual(migrated.recoveryDelay, settings.recoveryDelay)
        XCTAssertEqual(migrated.calibration, calibration)

        let storedObject = try storedSettingsObject(defaults: defaults, key: key)
        XCTAssertEqual(storedObject["schemaVersion"] as? Int, AttentionSettings.currentSchemaVersion)
    }

    func testUserDefaultsLoadMigratesOlderSchemaPayloadAndWritesBack() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.oldSchema.\(UUID().uuidString)"
        let calibration = calibrationSnapshot()
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .relaxed,
            headTurnThresholdDegrees: 20.0,
            speedControlAwayDelay: 0.6,
            pauseResumeAwayDelay: 1.4,
            recoveryDelay: 0.8,
            calibration: calibration
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object["schemaVersion"] = 0
        }

        let migrated = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(migrated.schemaVersion, AttentionSettings.currentSchemaVersion)
        XCTAssertEqual(migrated.mode, settings.mode)
        XCTAssertEqual(migrated.sensitivity, settings.sensitivity)
        XCTAssertEqual(migrated.headTurnThresholdDegrees, settings.headTurnThresholdDegrees)
        XCTAssertEqual(migrated.speedControlAwayDelay, settings.speedControlAwayDelay)
        XCTAssertEqual(migrated.pauseResumeAwayDelay, settings.pauseResumeAwayDelay)
        XCTAssertEqual(migrated.recoveryDelay, settings.recoveryDelay)
        XCTAssertEqual(migrated.calibration, calibration)

        let storedObject = try storedSettingsObject(defaults: defaults, key: key)
        XCTAssertEqual(storedObject["schemaVersion"] as? Int, AttentionSettings.currentSchemaVersion)
    }

    func testUserDefaultsLoadDefaultsNonFiniteNumericsAndInvalidSensitivity() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.nonfinite.\(UUID().uuidString)"
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .relaxed,
            headTurnThresholdDegrees: 24.0,
            speedControlAwayDelay: 1.0,
            pauseResumeAwayDelay: 1.5,
            recoveryDelay: 2.0,
            calibration: calibrationSnapshot()
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object["sensitivity"] = "overlySensitive"
            object["headTurnThresholdDegrees"] = "NaN"
            object["speedControlAwayDelay"] = "NaN"
            object["pauseResumeAwayDelay"] = "Infinity"
            object["recoveryDelay"] = "-Infinity"
        }

        let repaired = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(repaired.mode, .pauseResume)
        XCTAssertEqual(repaired.sensitivity, .balanced)
        XCTAssertEqual(repaired.headTurnThresholdDegrees, AttentionSettings.defaults.headTurnThresholdDegrees)
        XCTAssertEqual(repaired.speedControlAwayDelay, AttentionSettings.defaults.speedControlAwayDelay)
        XCTAssertEqual(repaired.pauseResumeAwayDelay, AttentionSettings.defaults.pauseResumeAwayDelay)
        XCTAssertEqual(repaired.recoveryDelay, AttentionSettings.defaults.recoveryDelay)
        XCTAssertNotNil(repaired.calibration)
        XCTAssertEqual(UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load(), repaired)
    }

    func testUserDefaultsLoadUsesValidSensitivityDefaultForNonFiniteThreshold() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.threshold.\(UUID().uuidString)"
        let settings = AttentionSettings(
            mode: .speedControl,
            sensitivity: .relaxed,
            headTurnThresholdDegrees: 24.0,
            speedControlAwayDelay: 0.8,
            pauseResumeAwayDelay: 1.2,
            recoveryDelay: 0.6,
            calibration: nil
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object["headTurnThresholdDegrees"] = "NaN"
        }

        let repaired = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(repaired.sensitivity, .relaxed)
        XCTAssertEqual(repaired.headTurnThresholdDegrees, AttentionSensitivity.relaxed.thresholdDegrees)
        XCTAssertEqual(UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load(), repaired)
    }

    func testUserDefaultsLoadPreservesSafeCalibrationAcrossScalarRepair() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.safeCalibration.\(UUID().uuidString)"
        let calibration = calibrationSnapshot()
        let settings = AttentionSettings.defaults.withCalibration(calibration)
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            object["speedControlAwayDelay"] = -1.0
        }

        let repaired = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(repaired.speedControlAwayDelay, 0.5)
        XCTAssertEqual(repaired.calibration, calibration)
        XCTAssertEqual(UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load(), repaired)
    }

    func testUserDefaultsLoadClearsUnsafeCalibrationWithoutResettingSafeFields() throws {
        let defaults = try uniqueDefaults()
        let key = "AttentionSettingsTests.unsafeCalibration.\(UUID().uuidString)"
        let settings = AttentionSettings(
            mode: .pauseResume,
            sensitivity: .relaxed,
            headTurnThresholdDegrees: 20.0,
            speedControlAwayDelay: 0.6,
            pauseResumeAwayDelay: 1.5,
            recoveryDelay: 0.8,
            calibration: calibrationSnapshot()
        )
        try writeMutatedSettings(settings, defaults: defaults, key: key) { object in
            setCalibrationNeutralPose("time", to: "NaN", in: &object)
        }

        let repaired = UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load()

        XCTAssertEqual(repaired.mode, settings.mode)
        XCTAssertEqual(repaired.sensitivity, settings.sensitivity)
        XCTAssertEqual(repaired.headTurnThresholdDegrees, settings.headTurnThresholdDegrees)
        XCTAssertEqual(repaired.speedControlAwayDelay, settings.speedControlAwayDelay)
        XCTAssertEqual(repaired.pauseResumeAwayDelay, settings.pauseResumeAwayDelay)
        XCTAssertEqual(repaired.recoveryDelay, settings.recoveryDelay)
        XCTAssertNil(repaired.calibration)
        XCTAssertEqual(UserDefaultsAttentionSettingsStore(defaults: defaults, key: key).load(), repaired)
    }
}

private func uniqueDefaults() throws -> UserDefaults {
    try XCTUnwrap(UserDefaults(suiteName: "AttentionSettingsTests.\(UUID().uuidString)"))
}

private func calibrationSnapshot() -> CalibrationSnapshot {
    CalibrationSnapshot(
        neutralPose: PoseSample(yawDegrees: 1.0, pitchDegrees: 2.0, rollDegrees: 3.0, time: 4.0),
        quality: .marginal,
        createdAt: Date(timeIntervalSince1970: 5.0)
    )
}

private func writeMutatedSettings(
    _ settings: AttentionSettings,
    defaults: UserDefaults,
    key: String,
    mutate: (inout [String: Any]) -> Void
) throws {
    let data = try JSONEncoder().encode(settings)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    mutate(&object)
    let mutatedData = try JSONSerialization.data(withJSONObject: object)
    defaults.set(mutatedData, forKey: key)
}

private func storedSettingsObject(defaults: UserDefaults, key: String) throws -> [String: Any] {
    let data = try XCTUnwrap(defaults.data(forKey: key))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func setCalibrationNeutralPose(_ field: String, to value: Any, in object: inout [String: Any]) {
    guard var calibration = object["calibration"] as? [String: Any],
          var neutralPose = calibration["neutralPose"] as? [String: Any] else {
        return
    }

    neutralPose[field] = value
    calibration["neutralPose"] = neutralPose
    object["calibration"] = calibration
}

private final class InMemoryAttentionSettingsStore: AttentionSettingsStoring {
    private var settings = AttentionSettings.defaults

    func load() -> AttentionSettings {
        settings
    }

    func save(_ settings: AttentionSettings) throws {
        self.settings = settings
    }

    func reset() throws {
        settings = .defaults
    }
}

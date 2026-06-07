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
            "Relaxed",
            "Balanced",
            "Strict"
        ])
        XCTAssertEqual(GlanceHoldMenuCopy.sensitivityLabel, "Head Turn Sensitivity")
        XCTAssertEqual(GlanceHoldMenuCopy.speedControlAwayDelayLabel, "Speed Control Away Delay")
        XCTAssertEqual(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel, "Pause/Resume Away Delay")
        XCTAssertEqual(GlanceHoldMenuCopy.recoveryDelayLabel, "Recovery Delay")
    }

    func testCompactDelayLabelsUseOneDecimalSecondSuffix() {
        XCTAssertEqual(TuningMenuPresentation.formatDelay(0.8), "0.8s")
        XCTAssertEqual(TuningMenuPresentation.formatDelay(1.2), "1.2s")
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

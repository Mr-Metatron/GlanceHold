import XCTest
@testable import GlanceHold

final class MenuOptionPresentationTests: XCTestCase {
    func testDefaultTuningParentLabelsIncludeCurrentValues() {
        let presentation = TuningMenuPresentation(settings: .defaults)

        XCTAssertEqual(
            presentation.sensitivityTitle,
            "\(GlanceHoldStrings.text(.tuningSensitivity)): \(GlanceHoldStrings.text(.sensitivityBalanced))"
        )
        XCTAssertEqual(
            presentation.speedControlAwayDelayTitle,
            "\(GlanceHoldStrings.text(.tuningSpeedControlAwayDelay)): \(GlanceHoldStrings.delaySeconds(0.8))"
        )
        XCTAssertEqual(
            presentation.pauseResumeAwayDelayTitle,
            "\(GlanceHoldStrings.text(.tuningPauseResumeAwayDelay)): \(GlanceHoldStrings.delaySeconds(1.2))"
        )
        XCTAssertEqual(
            presentation.recoveryDelayTitle,
            "\(GlanceHoldStrings.text(.tuningRecoveryDelay)): \(GlanceHoldStrings.delaySeconds(0.6))"
        )
    }

    func testDefaultTuningOptionsMarkExactlyOneSelectedValuePerGroup() {
        let presentation = TuningMenuPresentation(settings: .defaults)

        XCTAssertSingleSelection(presentation.sensitivityOptions, expectedTitle: GlanceHoldStrings.text(.sensitivityBalanced))
        XCTAssertSingleSelection(presentation.speedControlAwayDelayOptions, expectedTitle: GlanceHoldStrings.delaySeconds(0.8))
        XCTAssertSingleSelection(presentation.pauseResumeAwayDelayOptions, expectedTitle: GlanceHoldStrings.delaySeconds(1.2))
        XCTAssertSingleSelection(presentation.recoveryDelayOptions, expectedTitle: GlanceHoldStrings.delaySeconds(0.6))
    }

    func testDelaySelectionUsesToleranceForPersistedScalarValues() {
        var settings = AttentionSettings.defaults
        settings.speedControlAwayDelay = 0.80009

        let presentation = TuningMenuPresentation(settings: settings)

        XCTAssertSingleSelection(presentation.speedControlAwayDelayOptions, expectedTitle: GlanceHoldStrings.delaySeconds(0.8))
        XCTAssertEqual(TuningMenuPresentation.normalizedDelaySelection(settings.speedControlAwayDelay), 0.8)
    }

    func testDelaySelectionKeepsCustomValueOutsideTolerance() {
        XCTAssertEqual(TuningMenuPresentation.normalizedDelaySelection(0.73), 0.73)
    }

    func testModeDisplayNamesRemainStableForCheckedModePicker() {
        XCTAssertEqual(MonitoringMode.speedControl.displayName, GlanceHoldStrings.text(.modeSpeedControl))
        XCTAssertEqual(MonitoringMode.pauseResume.displayName, GlanceHoldStrings.text(.modePauseResume))
    }

    func testDefaultModeParentLabelIncludesCurrentMode() {
        XCTAssertEqual(
            ModeMenuPresentation.title(for: .speedControl),
            "\(GlanceHoldStrings.text(.menuMode)): \(GlanceHoldStrings.text(.modeSpeedControl))"
        )
    }

    func testAlternateModeParentLabelIncludesCurrentMode() {
        XCTAssertEqual(
            ModeMenuPresentation.title(for: .pauseResume),
            "\(GlanceHoldStrings.text(.menuMode)): \(GlanceHoldStrings.text(.modePauseResume))"
        )
    }

    func testDiagnosticModePresentationUsesLocalizedTitleAndCheckedState() {
        let disabled = DiagnosticModeMenuPresentation(settings: .disabled)
        let enabled = DiagnosticModeMenuPresentation(settings: DiagnosticSettings(isEnabled: true))

        XCTAssertEqual(disabled.title, GlanceHoldStrings.text(.menuDiagnosticMode))
        XCTAssertFalse(disabled.isSelected)
        XCTAssertEqual(enabled.title, GlanceHoldStrings.text(.menuDiagnosticMode))
        XCTAssertTrue(enabled.isSelected)
    }

    private func XCTAssertSingleSelection(
        _ options: [MenuOptionPresentation],
        expectedTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let selected = options.filter(\.isSelected)
        XCTAssertEqual(selected.map(\.title), [expectedTitle], file: file, line: line)
    }
}

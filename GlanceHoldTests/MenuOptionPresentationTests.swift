import XCTest
@testable import GlanceHold

final class MenuOptionPresentationTests: XCTestCase {
    func testDefaultTuningParentLabelsIncludeCurrentValues() {
        let presentation = TuningMenuPresentation(settings: .defaults)

        XCTAssertEqual(presentation.sensitivityTitle, "Head Turn Sensitivity: Balanced")
        XCTAssertEqual(presentation.speedControlAwayDelayTitle, "Speed Control Away Delay: 0.8s")
        XCTAssertEqual(presentation.pauseResumeAwayDelayTitle, "Pause/Resume Away Delay: 1.2s")
        XCTAssertEqual(presentation.recoveryDelayTitle, "Recovery Delay: 0.6s")
    }

    func testDefaultTuningOptionsMarkExactlyOneSelectedValuePerGroup() {
        let presentation = TuningMenuPresentation(settings: .defaults)

        XCTAssertSingleSelection(presentation.sensitivityOptions, expectedTitle: "Balanced")
        XCTAssertSingleSelection(presentation.speedControlAwayDelayOptions, expectedTitle: "0.8s")
        XCTAssertSingleSelection(presentation.pauseResumeAwayDelayOptions, expectedTitle: "1.2s")
        XCTAssertSingleSelection(presentation.recoveryDelayOptions, expectedTitle: "0.6s")
    }

    func testDelaySelectionUsesToleranceForPersistedScalarValues() {
        var settings = AttentionSettings.defaults
        settings.speedControlAwayDelay = 0.80009

        let presentation = TuningMenuPresentation(settings: settings)

        XCTAssertSingleSelection(presentation.speedControlAwayDelayOptions, expectedTitle: "0.8s")
    }

    func testModeDisplayNamesRemainStableForCheckedModePicker() {
        XCTAssertEqual(MonitoringMode.speedControl.displayName, "Speed Control")
        XCTAssertEqual(MonitoringMode.pauseResume.displayName, "Pause/Resume")
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

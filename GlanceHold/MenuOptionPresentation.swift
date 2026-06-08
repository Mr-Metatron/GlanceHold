import Foundation

struct MenuOptionPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
    let value: Double
}

enum ModeMenuPresentation {
    static func title(for mode: MonitoringMode) -> String {
        "\(GlanceHoldStrings.text(.menuMode)): \(mode.displayName)"
    }
}

struct TuningMenuPresentation: Equatable {
    static let delayChoices: [TimeInterval] = [0.5, 0.6, 0.8, 1.0, 1.2, 1.5, 2.0]
    static let delaySelectionTolerance: TimeInterval = 0.0001

    let sensitivityTitle: String
    let speedControlAwayDelayTitle: String
    let pauseResumeAwayDelayTitle: String
    let recoveryDelayTitle: String
    let sensitivityOptions: [MenuOptionPresentation]
    let speedControlAwayDelayOptions: [MenuOptionPresentation]
    let pauseResumeAwayDelayOptions: [MenuOptionPresentation]
    let recoveryDelayOptions: [MenuOptionPresentation]

    init(settings: AttentionSettings) {
        sensitivityTitle = "\(GlanceHoldMenuCopy.sensitivityLabel): \(settings.sensitivity.displayName)"
        speedControlAwayDelayTitle = "\(GlanceHoldMenuCopy.speedControlAwayDelayLabel): \(Self.formatDelay(settings.speedControlAwayDelay))"
        pauseResumeAwayDelayTitle = "\(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel): \(Self.formatDelay(settings.pauseResumeAwayDelay))"
        recoveryDelayTitle = "\(GlanceHoldMenuCopy.recoveryDelayLabel): \(Self.formatDelay(settings.recoveryDelay))"
        sensitivityOptions = AttentionSensitivity.allCases.map { sensitivity in
            MenuOptionPresentation(
                id: sensitivity.rawValue,
                title: sensitivity.displayName,
                isSelected: sensitivity == settings.sensitivity,
                value: sensitivity.thresholdDegrees
            )
        }
        speedControlAwayDelayOptions = Self.delayOptions(selectedDelay: settings.speedControlAwayDelay)
        pauseResumeAwayDelayOptions = Self.delayOptions(selectedDelay: settings.pauseResumeAwayDelay)
        recoveryDelayOptions = Self.delayOptions(selectedDelay: settings.recoveryDelay)
    }

    static func formatDelay(_ delay: TimeInterval) -> String {
        GlanceHoldStrings.delaySeconds(delay)
    }

    static func isSelected(delay: TimeInterval, selectedDelay: TimeInterval) -> Bool {
        abs(delay - selectedDelay) <= delaySelectionTolerance
    }

    static func normalizedDelaySelection(_ selectedDelay: TimeInterval) -> TimeInterval {
        delayChoices.first {
            isSelected(delay: $0, selectedDelay: selectedDelay)
        } ?? selectedDelay
    }

    private static func delayOptions(selectedDelay: TimeInterval) -> [MenuOptionPresentation] {
        delayChoices.map { delay in
            MenuOptionPresentation(
                id: formatDelay(delay),
                title: formatDelay(delay),
                isSelected: isSelected(delay: delay, selectedDelay: selectedDelay),
                value: delay
            )
        }
    }
}

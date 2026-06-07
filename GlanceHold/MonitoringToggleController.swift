import Foundation

enum MonitoringToggleController {
    static func resolveAction(for state: GlanceHoldState) -> GlanceHoldPrimaryAction {
        GlanceHoldPrimaryAction.resolve(for: state.status, hasCalibration: state.hasCalibration)
    }
}

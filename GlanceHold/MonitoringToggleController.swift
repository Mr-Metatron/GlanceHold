import Foundation

enum MonitoringLifecycleCleanupSource {
    case userDisable
    case quit
}

struct MonitoringLifecycleCleanupPlan: Equatable {
    var cancelPermissionRequest: Bool
    var stopPlaybackStatusUpdates: Bool
    var stopMonitoringToggleRequests: Bool
    var stopAttentionMonitor: Bool
    var stopPlaybackCoordinator: Bool
    var recordStoppedLastAction: Bool
    var terminateAfterCleanup: Bool
}

enum MonitoringToggleController {
    static func resolveAction(for state: GlanceHoldState) -> GlanceHoldPrimaryAction {
        GlanceHoldPrimaryAction.resolve(for: state.status, hasCalibration: state.hasCalibration)
    }

    static func cleanupPlan(for source: MonitoringLifecycleCleanupSource) -> MonitoringLifecycleCleanupPlan {
        switch source {
        case .userDisable:
            MonitoringLifecycleCleanupPlan(
                cancelPermissionRequest: true,
                stopPlaybackStatusUpdates: false,
                stopMonitoringToggleRequests: false,
                stopAttentionMonitor: true,
                stopPlaybackCoordinator: true,
                recordStoppedLastAction: true,
                terminateAfterCleanup: false
            )
        case .quit:
            MonitoringLifecycleCleanupPlan(
                cancelPermissionRequest: true,
                stopPlaybackStatusUpdates: true,
                stopMonitoringToggleRequests: true,
                stopAttentionMonitor: true,
                stopPlaybackCoordinator: true,
                recordStoppedLastAction: false,
                terminateAfterCleanup: true
            )
        }
    }
}

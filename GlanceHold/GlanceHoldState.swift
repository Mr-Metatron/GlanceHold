import Foundation

enum MonitoringMode: CaseIterable, Equatable, Hashable {
    case speedControl
    case pauseResume

    var displayName: String {
        switch self {
        case .speedControl:
            "Speed Control"
        case .pauseResume:
            "Pause/Resume"
        }
    }
}

enum MonitoringStatus: CaseIterable, Equatable {
    case off
    case cameraPermissionNeeded
    case readyAfterCalibration
    case facing
    case lookingAway
    case noFaceDetected
    case recovering
    case iinaUnavailable

    var visibleTitle: String {
        switch self {
        case .off:
            "Off"
        case .cameraPermissionNeeded:
            "Camera Permission Needed"
        case .readyAfterCalibration:
            "Ready After Calibration"
        case .facing:
            "Facing"
        case .lookingAway:
            "Looking Away"
        case .noFaceDetected:
            "No Face Detected"
        case .recovering:
            "Recovering"
        case .iinaUnavailable:
            ["I", "INA Unavailable"].joined()
        }
    }
}

struct GlanceHoldState: Equatable {
    var mode: MonitoringMode
    var status: MonitoringStatus

    init(mode: MonitoringMode = .speedControl, status: MonitoringStatus = .off) {
        self.mode = mode
        self.status = status
    }

    var isMonitoringActive: Bool {
        switch status {
        case .facing, .lookingAway, .noFaceDetected, .recovering, .iinaUnavailable:
            true
        case .off, .cameraPermissionNeeded, .readyAfterCalibration:
            false
        }
    }

    mutating func enableMonitoring() {
        guard status == .off else {
            return
        }

        status = .cameraPermissionNeeded
    }

    mutating func disableMonitoring() {
        status = .off
    }

    mutating func selectMode(_ mode: MonitoringMode) {
        self.mode = mode
    }
}

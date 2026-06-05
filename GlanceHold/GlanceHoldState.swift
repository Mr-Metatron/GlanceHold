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
    case cameraPermissionDenied
    case requestingCameraPermission
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
        case .cameraPermissionDenied:
            "Camera Permission Denied"
        case .requestingCameraPermission:
            "Requesting Camera Permission"
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

    var detailText: String {
        switch self {
        case .cameraPermissionDenied:
            "Camera permission is denied. Allow camera access in System Settings, then enable monitoring again."
        case .iinaUnavailable:
            "Monitoring cannot start yet because IINA is unavailable."
        default:
            ""
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
        case .off, .cameraPermissionNeeded, .cameraPermissionDenied, .requestingCameraPermission, .readyAfterCalibration:
            false
        }
    }

    mutating func enableMonitoring() {
        guard status == .off else {
            return
        }

        status = .cameraPermissionNeeded
    }

    func resolvedStatusAfterEnable(permissionProvider: CameraPermissionProviding) async -> MonitoringStatus {
        guard status == .off || status == .cameraPermissionNeeded || status == .cameraPermissionDenied || status == .requestingCameraPermission else {
            return status
        }

        switch permissionProvider.authorizationStatus() {
        case .granted:
            return .readyAfterCalibration
        case .denied, .restricted:
            return .cameraPermissionDenied
        case .undetermined:
            return await permissionProvider.requestAccess() ? .readyAfterCalibration : .cameraPermissionDenied
        }
    }

    mutating func enableMonitoring(permissionProvider: CameraPermissionProviding) async {
        guard status != .requestingCameraPermission else {
            return
        }

        status = .requestingCameraPermission
        status = await resolvedStatusAfterEnable(permissionProvider: permissionProvider)
    }

    mutating func disableMonitoring() {
        status = .off
    }

    mutating func selectMode(_ mode: MonitoringMode) {
        self.mode = mode
    }
}

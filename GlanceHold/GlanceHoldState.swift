import Foundation

enum MonitoringMode: String, CaseIterable, Equatable, Hashable, Codable {
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

enum MonitoringStatus: Equatable {
    case off
    case cameraPermissionNeeded
    case cameraPermissionDenied
    case requestingCameraPermission
    case cameraUnavailable
    case needsCalibration
    case calibratingFacingPose
    case calibrationFailed(previousKept: Bool)
    case readyAfterCalibration
    case readyAfterMarginalCalibration
    case facing
    case lookingAway
    case noFaceDetected
    case recovering
    case iinaUnavailable

    static var visibleVocabulary: [String] {
        [
            "Off",
            "Camera Permission Needed",
            "Camera Permission Denied",
            "Camera Unavailable",
            "Needs Calibration",
            "Calibrating Facing Pose",
            "Calibration Failed",
            "Requesting Camera Permission",
            "Ready After Calibration",
            "Facing",
            "Looking Away",
            "No Face Detected",
            "Recovering",
            ["I", "INA Unavailable"].joined()
        ]
    }

    init(monitorState: AttentionMonitorState) {
        switch monitorState {
        case .off:
            self = .off
        case .needsCalibration:
            self = .needsCalibration
        case .calibrating:
            self = .calibratingFacingPose
        case .ready:
            self = .readyAfterCalibration
        case .facing:
            self = .facing
        case .lookingAway:
            self = .lookingAway
        case .noFaceDetected:
            self = .noFaceDetected
        case .recovering:
            self = .recovering
        case .cameraPermissionDenied:
            self = .cameraPermissionDenied
        case .cameraUnavailable:
            self = .cameraUnavailable
        case .calibrationFailed(let previousKept):
            self = .calibrationFailed(previousKept: previousKept)
        case .unavailable:
            self = .cameraUnavailable
        }
    }

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
        case .cameraUnavailable:
            "Camera Unavailable"
        case .needsCalibration:
            "Needs Calibration"
        case .calibratingFacingPose:
            "Calibrating Facing Pose"
        case .calibrationFailed:
            "Calibration Failed"
        case .readyAfterCalibration, .readyAfterMarginalCalibration:
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
        case .cameraPermissionNeeded, .needsCalibration:
            GlanceHoldMenuCopy.calibrationNeededBody
        case .cameraPermissionDenied:
            "Camera permission is denied. Allow camera access in System Settings, then enable monitoring again."
        case .cameraUnavailable:
            "Camera is unavailable. Check camera access or close other apps using the camera, then try again."
        case .calibratingFacingPose:
            "Face the screen steadily while GlanceHold calibrates your facing pose."
        case .calibrationFailed(let previousKept):
            previousKept
                ? "Calibration failed because no stable face was detected. Your previous calibration was kept."
                : "Calibration failed because no stable face was detected. Try again while facing the screen."
        case .readyAfterMarginalCalibration:
            "Recalibration recommended. Monitoring can continue with the current calibration."
        case .iinaUnavailable:
            "Monitoring cannot start yet because \(["I", "INA"].joined()) is unavailable."
        default:
            ""
        }
    }
}

enum GlanceHoldMenuCopy {
    static let tuningSectionTitle = "Tuning"
    static let sensitivityLabel = "Head Turn Sensitivity"
    static let speedControlAwayDelayLabel = "Speed Control Away Delay"
    static let pauseResumeAwayDelayLabel = "Pause/Resume Away Delay"
    static let recoveryDelayLabel = "Recovery Delay"
    static let calibrationNeededBody = "Calibrate your facing-screen pose before monitoring can use camera signals. Camera access starts only after you choose calibration or monitoring."
    static let privacyNote = "Camera stays on this Mac. Frames are not saved or uploaded."
    static let marginalReplacementPrompt = "The new calibration is usable but less stable than the current one. Keep the current calibration or use the new one?"
    static let keepCurrentCalibrationButton = "Keep Current Calibration"
    static let useNewCalibrationButton = "Use New Calibration"
    static let resetConfirmationMessage = "Reset Calibration: confirm before removing saved calibration; after reset, monitoring returns to Calibration Needed."
}

struct GlanceHoldState: Equatable {
    var settings: AttentionSettings
    var status: MonitoringStatus

    init(mode: MonitoringMode = .speedControl, status: MonitoringStatus = .off, settings: AttentionSettings = .defaults) {
        var resolvedSettings = settings
        resolvedSettings.mode = mode
        self.settings = resolvedSettings
        self.status = status
    }

    var mode: MonitoringMode {
        get {
            settings.mode
        }
        set {
            settings.mode = newValue
        }
    }

    var hasCalibration: Bool {
        settings.calibration != nil
    }

    var isMonitoringActive: Bool {
        switch status {
        case .facing, .lookingAway, .noFaceDetected, .recovering, .iinaUnavailable:
            true
        case .off, .cameraPermissionNeeded, .cameraPermissionDenied, .requestingCameraPermission, .cameraUnavailable, .needsCalibration, .calibratingFacingPose, .calibrationFailed, .readyAfterCalibration, .readyAfterMarginalCalibration:
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
        guard status == .off || status == .cameraPermissionNeeded || status == .cameraPermissionDenied || status == .requestingCameraPermission || status == .cameraUnavailable else {
            return status
        }

        guard hasCalibration else {
            return .needsCalibration
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

    mutating func updateSettings(_ settings: AttentionSettings) {
        self.settings = settings
    }

    mutating func apply(monitorState: AttentionMonitorState) {
        status = MonitoringStatus(monitorState: monitorState)
        if status == .readyAfterCalibration, settings.calibration?.quality == .marginal {
            status = .readyAfterMarginalCalibration
        }
    }
}

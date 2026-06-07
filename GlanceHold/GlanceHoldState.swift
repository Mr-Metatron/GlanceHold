import Foundation

enum MonitoringMode: String, CaseIterable, Equatable, Hashable, Codable {
    case speedControl
    case pauseResume

    var displayName: String {
        switch self {
        case .speedControl:
            GlanceHoldStrings.text(.modeSpeedControl)
        case .pauseResume:
            GlanceHoldStrings.text(.modePauseResume)
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
            off.visibleTitle,
            cameraPermissionNeeded.visibleTitle,
            cameraPermissionDenied.visibleTitle,
            cameraUnavailable.visibleTitle,
            needsCalibration.visibleTitle,
            calibratingFacingPose.visibleTitle,
            calibrationFailed(previousKept: false).visibleTitle,
            requestingCameraPermission.visibleTitle,
            readyAfterCalibration.visibleTitle,
            facing.visibleTitle,
            lookingAway.visibleTitle,
            noFaceDetected.visibleTitle,
            recovering.visibleTitle,
            iinaUnavailable.visibleTitle
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
            GlanceHoldStrings.text(.monitoringOffTitle)
        case .cameraPermissionNeeded:
            GlanceHoldStrings.text(.monitoringCameraPermissionNeededTitle)
        case .cameraPermissionDenied:
            GlanceHoldStrings.text(.monitoringCameraPermissionDeniedTitle)
        case .requestingCameraPermission:
            GlanceHoldStrings.text(.monitoringRequestingCameraPermissionTitle)
        case .cameraUnavailable:
            GlanceHoldStrings.text(.monitoringCameraUnavailableTitle)
        case .needsCalibration:
            GlanceHoldStrings.text(.monitoringNeedsCalibrationTitle)
        case .calibratingFacingPose:
            GlanceHoldStrings.text(.monitoringCalibratingFacingPoseTitle)
        case .calibrationFailed:
            GlanceHoldStrings.text(.monitoringCalibrationFailedTitle)
        case .readyAfterCalibration, .readyAfterMarginalCalibration:
            GlanceHoldStrings.text(.monitoringReadyAfterCalibrationTitle)
        case .facing:
            GlanceHoldStrings.text(.monitoringFacingTitle)
        case .lookingAway:
            GlanceHoldStrings.text(.monitoringLookingAwayTitle)
        case .noFaceDetected:
            GlanceHoldStrings.text(.monitoringNoFaceDetectedTitle)
        case .recovering:
            GlanceHoldStrings.text(.monitoringRecoveringTitle)
        case .iinaUnavailable:
            GlanceHoldStrings.text(.monitoringIINAUnavailableTitle)
        }
    }

    var detailText: String {
        switch self {
        case .cameraPermissionNeeded, .needsCalibration:
            GlanceHoldMenuCopy.calibrationNeededBody
        case .cameraPermissionDenied:
            GlanceHoldStrings.text(.monitoringCameraPermissionDeniedDetail)
        case .cameraUnavailable:
            GlanceHoldStrings.text(.monitoringCameraUnavailableDetail)
        case .calibratingFacingPose:
            GlanceHoldStrings.text(.monitoringCalibratingFacingPoseDetail)
        case .calibrationFailed(let previousKept):
            previousKept
                ? GlanceHoldStrings.text(.monitoringCalibrationFailedPreviousKeptDetail)
                : GlanceHoldStrings.text(.monitoringCalibrationFailedRetryDetail)
        case .readyAfterMarginalCalibration:
            GlanceHoldStrings.text(.monitoringReadyAfterMarginalCalibrationDetail)
        case .iinaUnavailable:
            GlanceHoldStrings.text(.monitoringIINAUnavailableDetail)
        default:
            ""
        }
    }
}

enum PlayerControlStatus: Equatable {
    case unavailable
    case setupNeeded
    case idle
    case paused
    case playing
    case notControllable

    static var visibleVocabulary: [String] {
        [
            unavailable.visibleTitle,
            setupNeeded.visibleTitle,
            idle.visibleTitle,
            paused.visibleTitle,
            playing.visibleTitle,
            notControllable.visibleTitle
        ]
    }

    init(coordinatorState: PlaybackCoordinatorState) {
        if coordinatorState.stoppedReason != nil || !coordinatorState.isPlayerControllable {
            switch coordinatorState.playerSnapshot.playbackState {
            case .idle:
                self = .idle
            case .setupNeeded:
                self = .setupNeeded
            case .playing, .paused:
                self = .notControllable
            case .playerUnavailable:
                self = .unavailable
            }
            return
        }

        switch coordinatorState.playerSnapshot.playbackState {
        case .playing:
            self = .playing
        case .paused:
            self = .paused
        case .idle:
            self = .idle
        case .setupNeeded:
            self = .setupNeeded
        case .playerUnavailable:
            self = .unavailable
        }
    }

    var visibleTitle: String {
        switch self {
        case .unavailable:
            GlanceHoldStrings.text(.playerUnavailableTitle)
        case .setupNeeded:
            GlanceHoldStrings.text(.playerSetupNeededTitle)
        case .idle:
            GlanceHoldStrings.text(.playerIdleTitle)
        case .paused:
            GlanceHoldStrings.text(.playerPausedTitle)
        case .playing:
            GlanceHoldStrings.text(.playerPlayingTitle)
        case .notControllable:
            GlanceHoldStrings.text(.playerNotControllableTitle)
        }
    }

    var detailText: String {
        switch self {
        case .unavailable:
            GlanceHoldStrings.text(.playerUnavailableDetail)
        case .setupNeeded:
            GlanceHoldStrings.text(.playerSetupNeededDetail)
        case .idle:
            GlanceHoldStrings.text(.playerIdleDetail)
        case .notControllable:
            GlanceHoldStrings.text(.playerNotControllableDetail)
        case .paused, .playing:
            ""
        }
    }
}

enum GlanceHoldMenuCopy {
    static var tuningSectionTitle: String { GlanceHoldStrings.text(.tuningSection) }
    static var sensitivityLabel: String { GlanceHoldStrings.text(.tuningSensitivity) }
    static var speedControlAwayDelayLabel: String { GlanceHoldStrings.text(.tuningSpeedControlAwayDelay) }
    static var pauseResumeAwayDelayLabel: String { GlanceHoldStrings.text(.tuningPauseResumeAwayDelay) }
    static var recoveryDelayLabel: String { GlanceHoldStrings.text(.tuningRecoveryDelay) }
    static var calibrationNeededBody: String { GlanceHoldStrings.text(.monitoringCalibrationNeededDetail) }
    static var privacyNote: String { GlanceHoldStrings.text(.privacyNote) }
    static var marginalReplacementPrompt: String { GlanceHoldStrings.text(.alertMarginalReplacementPrompt) }
    static var keepCurrentCalibrationButton: String { GlanceHoldStrings.text(.alertKeepCurrentCalibration) }
    static var useNewCalibrationButton: String { GlanceHoldStrings.text(.alertUseNewCalibration) }
    static var resetConfirmationMessage: String { GlanceHoldStrings.text(.alertResetConfirmationMessage) }
}

struct GlanceHoldState: Equatable {
    var settings: AttentionSettings
    var status: MonitoringStatus
    var playerStatus: PlayerControlStatus?

    init(
        mode: MonitoringMode = .speedControl,
        status: MonitoringStatus = .off,
        playerStatus: PlayerControlStatus? = nil,
        settings: AttentionSettings = .defaults
    ) {
        var resolvedSettings = settings
        resolvedSettings.mode = mode
        self.settings = resolvedSettings
        self.status = status
        self.playerStatus = playerStatus
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

        switch permissionProvider.authorizationStatus() {
        case .granted:
            return hasCalibration ? .readyAfterCalibration : .needsCalibration
        case .denied, .restricted:
            return .cameraPermissionDenied
        case .undetermined:
            guard await permissionProvider.requestAccess() else {
                return .cameraPermissionDenied
            }
            return hasCalibration ? .readyAfterCalibration : .needsCalibration
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

    mutating func stopMonitoringAfterManualPlayerTakeover() {
        status = .off
    }

    mutating func selectMode(_ mode: MonitoringMode) {
        self.mode = mode
    }

    mutating func updateSettings(_ settings: AttentionSettings) {
        self.settings = settings
    }

    mutating func apply(playerControlState: PlaybackCoordinatorState) {
        playerStatus = PlayerControlStatus(coordinatorState: playerControlState)
    }

    mutating func apply(monitorState: AttentionMonitorState) {
        status = MonitoringStatus(monitorState: monitorState)
        if status == .readyAfterCalibration, settings.calibration?.quality == .marginal {
            status = .readyAfterMarginalCalibration
        }
    }
}

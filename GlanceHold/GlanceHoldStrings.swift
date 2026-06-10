import Foundation

enum GlanceHoldStrings {
    enum Key: String, CaseIterable {
        case appName = "app.name"
        case aboutWindowTitle = "app.about.window.title"
        case menuMode = "menu.mode"
        case menuStatusFormat = "menu.status.format"
        case menuPlayerFormat = "menu.player.format"
        case menuLastActionFormat = "menu.lastAction.format"
        case menuAbout = "menu.about"
        case menuDiagnosticMode = "menu.diagnosticMode"
        case menuQuit = "menu.quit"
        case lastActionHeldSpeedAtOne = "lastAction.heldSpeedAtOne"
        case lastActionRestoredSpeed = "lastAction.restoredSpeed"
        case lastActionPausedByGlanceHold = "lastAction.pausedByGlanceHold"
        case lastActionResumedPlayback = "lastAction.resumedPlayback"
        case lastActionManualPauseDetected = "lastAction.manualPauseDetected"
        case lastActionStoppedMonitoring = "lastAction.stoppedMonitoring"
        case actionCalibrate = "action.calibrate"
        case actionRecalibrate = "action.recalibrate"
        case actionResetCalibration = "action.resetCalibration"
        case actionEnableMonitoring = "action.enableMonitoring"
        case actionDisableMonitoring = "action.disableMonitoring"
        case actionWaitingCameraPermission = "action.waitingCameraPermission"
        case actionOpenCameraSettings = "action.openCameraSettings"
        case modeSpeedControl = "menu.mode.speedControl"
        case modePauseResume = "menu.mode.pauseResume"
        case monitoringOffTitle = "status.monitoring.off"
        case monitoringCameraPermissionNeededTitle = "status.monitoring.cameraPermissionNeeded"
        case monitoringCameraPermissionDeniedTitle = "status.monitoring.cameraPermissionDenied"
        case monitoringRequestingCameraPermissionTitle = "status.monitoring.requestingCameraPermission"
        case monitoringCameraUnavailableTitle = "status.monitoring.cameraUnavailable"
        case monitoringNeedsCalibrationTitle = "status.monitoring.needsCalibration"
        case monitoringCalibratingFacingPoseTitle = "status.monitoring.calibratingFacingPose"
        case monitoringCalibrationFailedTitle = "status.monitoring.calibrationFailed"
        case monitoringReadyAfterCalibrationTitle = "status.monitoring.readyAfterCalibration"
        case monitoringFacingTitle = "status.monitoring.facing"
        case monitoringLookingAwayTitle = "status.monitoring.lookingAway"
        case monitoringNoFaceDetectedTitle = "status.monitoring.noFaceDetected"
        case monitoringRecoveringTitle = "status.monitoring.recovering"
        case monitoringIINAUnavailableTitle = "status.monitoring.iinaUnavailable"
        case playerUnavailableTitle = "status.player.unavailable"
        case playerSetupNeededTitle = "status.player.setupNeeded"
        case playerPluginUpdateRequiredTitle = "status.player.pluginUpdateRequired"
        case playerIdleTitle = "status.player.idle"
        case playerPausedTitle = "status.player.paused"
        case playerPlayingTitle = "status.player.playing"
        case playerNotControllableTitle = "status.player.notControllable"
        case monitoringCalibrationNeededDetail = "detail.monitoring.calibrationNeeded"
        case monitoringCameraPermissionDeniedDetail = "detail.monitoring.cameraPermissionDenied"
        case monitoringCameraUnavailableDetail = "detail.monitoring.cameraUnavailable"
        case monitoringCalibratingFacingPoseDetail = "detail.monitoring.calibratingFacingPose"
        case monitoringCalibrationFailedPreviousKeptDetail = "detail.monitoring.calibrationFailed.previousKept"
        case monitoringCalibrationFailedRetryDetail = "detail.monitoring.calibrationFailed.retry"
        case monitoringReadyAfterMarginalCalibrationDetail = "detail.monitoring.readyAfterMarginalCalibration"
        case monitoringIINAUnavailableDetail = "detail.monitoring.iinaUnavailable"
        case playerUnavailableDetail = "detail.player.unavailable"
        case playerSetupNeededDetail = "detail.player.setupNeeded"
        case playerPluginUpdateRequiredDetail = "detail.player.pluginUpdateRequired"
        case playerIdleDetail = "detail.player.idle"
        case playerNotControllableDetail = "detail.player.notControllable"
        case tuningSection = "tuning.section"
        case tuningSensitivity = "tuning.sensitivity"
        case tuningSpeedControlAwayDelay = "tuning.speedControlAwayDelay"
        case tuningPauseResumeAwayDelay = "tuning.pauseResumeAwayDelay"
        case tuningRecoveryDelay = "tuning.recoveryDelay"
        case sensitivityRelaxed = "tuning.sensitivity.relaxed"
        case sensitivityBalanced = "tuning.sensitivity.balanced"
        case sensitivityStrict = "tuning.sensitivity.strict"
        case alertCancel = "alert.cancel"
        case alertRecalibrationRecommended = "alert.recalibrationRecommended"
        case alertMarginalReplacementPrompt = "alert.marginalReplacementPrompt"
        case alertKeepCurrentCalibration = "alert.keepCurrentCalibration"
        case alertUseNewCalibration = "alert.useNewCalibration"
        case alertResetConfirmationMessage = "alert.resetConfirmationMessage"
        case shortcutToggleMonitoring = "shortcut.toggle.monitoring"
        case aboutTitle = "about.title"
        case aboutSubtitle = "about.subtitle"
        case aboutCalibrationBody = "about.calibrationBody"
        case aboutPrivacyBody = "about.privacyBody"
        case privacyPermissionExplanation = "privacy.permissionExplanation"
        case privacyNote = "privacy.note"
        case accessibilityStatusFormat = "accessibility.status.format"
        case accessibilityPlayerFormat = "accessibility.player.format"
        case formatDelaySeconds = "format.delay.seconds"
    }

    static func text(_ key: Key, localeIdentifier: String? = nil) -> String {
        localizedString(forKey: key.rawValue, localeIdentifier: localeIdentifier)
    }

    static func format(_ key: Key, _ arguments: CVarArg..., localeIdentifier: String? = nil) -> String {
        let format = text(key, localeIdentifier: localeIdentifier)
        return String(format: format, locale: locale(for: localeIdentifier), arguments: arguments)
    }

    static func delaySeconds(_ delay: TimeInterval, localeIdentifier: String? = nil) -> String {
        format(.formatDelaySeconds, delay, localeIdentifier: localeIdentifier)
    }

    private static func localizedString(forKey key: String, localeIdentifier: String?) -> String {
        if let localeIdentifier,
           let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }

        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private static func locale(for localeIdentifier: String?) -> Locale {
        if let localeIdentifier {
            Locale(identifier: localeIdentifier)
        } else {
            Locale.current
        }
    }
}

import SwiftUI

@main
struct GlanceHoldApp: App {
    private let settingsStore: UserDefaultsAttentionSettingsStore
    private let monitor: AttentionMonitor
    @State private var glanceHoldState: GlanceHoldState

    init() {
        let settingsStore = UserDefaultsAttentionSettingsStore()
        let loadedSettings = settingsStore.load()
        self.settingsStore = settingsStore
        self.monitor = AttentionMonitor(
            permissionProvider: CameraPermissionClient.live,
            settingsStore: settingsStore,
            capture: LiveCameraFrameCapture(),
            analyzer: LiveVisionAttentionAnalyzer()
        )
        _glanceHoldState = State(initialValue: GlanceHoldState(mode: loadedSettings.mode, settings: loadedSettings))
    }

    var body: some Scene {
        MenuBarExtra("GlanceHold", systemImage: "display") {
            GlanceHoldMenu(state: $glanceHoldState, monitor: monitor)
        }

        Window("About GlanceHold", id: "about") {
            ContentView()
        }
        .defaultSize(width: 420, height: 260)
    }
}

enum GlanceHoldPrimaryAction: Equatable {
    case calibrate
    case recalibrate
    case resetCalibration
    case enable
    case disable
    case wait
    case openCameraSettings

    static func resolve(for status: MonitoringStatus) -> GlanceHoldPrimaryAction {
        switch status {
        case .off, .cameraPermissionNeeded:
            .enable
        case .requestingCameraPermission, .calibratingFacingPose:
            .wait
        case .cameraPermissionDenied:
            .openCameraSettings
        default:
            .disable
        }
    }

    static func resolve(for status: MonitoringStatus, hasCalibration: Bool) -> GlanceHoldPrimaryAction {
        switch status {
        case .off:
            hasCalibration ? .enable : .calibrate
        case .cameraPermissionNeeded, .needsCalibration, .calibrationFailed:
            .calibrate
        case .requestingCameraPermission, .calibratingFacingPose:
            .wait
        case .cameraPermissionDenied:
            .openCameraSettings
        case .cameraUnavailable, .readyAfterCalibration, .readyAfterMarginalCalibration:
            hasCalibration ? .enable : .calibrate
        default:
            .disable
        }
    }

    var title: String {
        switch self {
        case .calibrate:
            "Calibrate Facing Pose"
        case .recalibrate:
            "Recalibrate Facing Pose"
        case .resetCalibration:
            "Reset Calibration"
        case .enable:
            "Enable Monitoring"
        case .disable:
            "Disable Monitoring"
        case .wait:
            "Requesting Camera Permission..."
        case .openCameraSettings:
            "Open Camera Settings..."
        }
    }

    var isEnabled: Bool {
        self != .wait
    }
}

private struct GlanceHoldMenu: View {
    @Binding var state: GlanceHoldState
    let monitor: AttentionMonitor
    @State private var permissionRequestID: UUID?
    @Environment(\.openWindow) private var openWindow

    private let permissionExplanation = "GlanceHold uses the camera only on this Mac to tell whether you are facing the screen. Frames are not saved or uploaded."
    private let delayChoices: [TimeInterval] = [0.5, 0.8, 1.0, 1.2, 1.5, 2.0]

    private var primaryAction: GlanceHoldPrimaryAction {
        GlanceHoldPrimaryAction.resolve(for: state.status, hasCalibration: state.hasCalibration)
    }

    var body: some View {
        Group {
            Text("Status: \(state.status.visibleTitle)")
                .accessibilityLabel("Status: \(state.status.visibleTitle)")

            if state.status == .cameraPermissionNeeded {
                Text(permissionExplanation)
                    .foregroundStyle(.secondary)
            } else if !state.status.detailText.isEmpty {
                Text(state.status.detailText)
                    .foregroundStyle(state.status == .cameraPermissionDenied ? .orange : .secondary)
            }

            Divider()

            Button(primaryAction.title) {
                performPrimaryAction(primaryAction)
            }
            .disabled(!primaryAction.isEnabled)

            Divider()

            Picker("Mode", selection: modeBinding) {
                Text("Speed Control").tag(MonitoringMode.speedControl)
                Text("Pause/Resume").tag(MonitoringMode.pauseResume)
            }

            Divider()

            Text(GlanceHoldMenuCopy.tuningSectionTitle)
                .foregroundStyle(.secondary)

            Menu(GlanceHoldMenuCopy.sensitivityLabel) {
                ForEach(AttentionSensitivity.allCases, id: \.self) { sensitivity in
                    Button(sensitivity.displayName) {
                        updateSettings(state.settings.withSensitivity(sensitivity))
                    }
                }
            }

            Menu(GlanceHoldMenuCopy.speedControlAwayDelayLabel) {
                ForEach(delayChoices, id: \.self) { delay in
                    Button(formatDelay(delay)) {
                        var settings = state.settings
                        settings.speedControlAwayDelay = delay
                        updateSettings(settings)
                    }
                }
            }

            Menu(GlanceHoldMenuCopy.pauseResumeAwayDelayLabel) {
                ForEach(delayChoices, id: \.self) { delay in
                    Button(formatDelay(delay)) {
                        var settings = state.settings
                        settings.pauseResumeAwayDelay = delay
                        updateSettings(settings)
                    }
                }
            }

            Menu(GlanceHoldMenuCopy.recoveryDelayLabel) {
                ForEach(delayChoices, id: \.self) { delay in
                    Button(formatDelay(delay)) {
                        var settings = state.settings
                        settings.recoveryDelay = delay
                        updateSettings(settings)
                    }
                }
            }

            if state.hasCalibration {
                Divider()

                Button(GlanceHoldPrimaryAction.recalibrate.title) {
                    startCalibration()
                }

                Button(GlanceHoldPrimaryAction.resetCalibration.title, role: .destructive) {
                    resetCalibrationWithConfirmation()
                }
            }

            Text(GlanceHoldMenuCopy.privacyNote)
                .foregroundStyle(.secondary)

            Divider()

            Button("About GlanceHold...") {
                openWindow(id: "about")
            }

            Button("Quit GlanceHold") {
                monitor.stopMonitoring()
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear(perform: installMonitorStateHandler)
    }

    private var modeBinding: Binding<MonitoringMode> {
        Binding(
            get: {
                state.mode
            },
            set: { mode in
                var settings = state.settings
                settings.mode = mode
                updateSettings(settings)
            }
        )
    }

    private func performPrimaryAction(_ action: GlanceHoldPrimaryAction) {
        switch action {
        case .calibrate, .recalibrate:
            startCalibration()
        case .resetCalibration:
            resetCalibrationWithConfirmation()
        case .enable:
            enableMonitoring()
        case .disable:
            permissionRequestID = nil
            monitor.stopMonitoring()
            state.disableMonitoring()
        case .wait:
            break
        case .openCameraSettings:
            openCameraSettings()
        }
    }

    private func enableMonitoring() {
        guard state.status != .requestingCameraPermission else {
            return
        }

        let requestID = UUID()
        permissionRequestID = requestID
        state.status = .requestingCameraPermission

        Task {
            await monitor.startMonitoring()
            await MainActor.run {
                guard permissionRequestID == requestID else {
                    return
                }

                permissionRequestID = nil
                state.updateSettings(monitor.settings)
                state.apply(monitorState: monitor.state)
            }
        }
    }

    private func startCalibration() {
        let requestID = UUID()
        permissionRequestID = requestID
        state.status = .requestingCameraPermission

        Task {
            let result = await monitor.captureCalibrationSampleSet()
            await MainActor.run {
                guard permissionRequestID == requestID else {
                    return
                }

                permissionRequestID = nil
                handleCalibrationResult(result)
                state.updateSettings(monitor.settings)
                state.apply(monitorState: monitor.state)
            }
        }
    }

    private func updateSettings(_ settings: AttentionSettings) {
        do {
            try monitor.updateSettings(settings)
            state.updateSettings(settings)
        } catch {
            state.status = .cameraUnavailable
        }
    }

    private func resetCalibrationWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = GlanceHoldPrimaryAction.resetCalibration.title
        alert.informativeText = GlanceHoldMenuCopy.resetConfirmationMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: GlanceHoldPrimaryAction.resetCalibration.title)

        guard alert.runModal() == .alertSecondButtonReturn else {
            return
        }

        do {
            try monitor.resetCalibration()
            state.updateSettings(monitor.settings)
            state.apply(monitorState: monitor.state)
        } catch {
            state.status = .cameraUnavailable
        }
    }

    private func handleCalibrationResult(_ result: CalibrationResult) {
        guard case .needsReplacementConfirmation(let candidate, let existing) = result else {
            return
        }

        let decision: CalibrationReplacementDecision = confirmMarginalReplacement() ? .useNew : .keepCurrent
        do {
            try monitor.applyCalibrationReplacement(candidate: candidate, existing: existing, decision: decision)
        } catch {
            state.status = .cameraUnavailable
        }
    }

    private func confirmMarginalReplacement() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Recalibration recommended"
        alert.informativeText = GlanceHoldMenuCopy.marginalReplacementPrompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: GlanceHoldMenuCopy.keepCurrentCalibrationButton)
        alert.addButton(withTitle: GlanceHoldMenuCopy.useNewCalibrationButton)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func formatDelay(_ delay: TimeInterval) -> String {
        String(format: "%.1f seconds", delay)
    }

    private func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func installMonitorStateHandler() {
        monitor.stateDidChange = { monitorState, settings in
            Task { @MainActor in
                state.updateSettings(settings)
                state.apply(monitorState: monitorState)
            }
        }
    }
}

import SwiftUI

@main
struct GlanceHoldApp: App {
    private let settingsStore: UserDefaultsAttentionSettingsStore
    private let diagnosticSettingsStore: UserDefaultsDiagnosticSettingsStore
    private let diagnosticSettings: DiagnosticSettings
    private let diagnosticRecorder: LiveDiagnosticRecorder
    private let monitor: AttentionMonitor
    private let bridgeClient: IINAPluginBridgeClient
    @State private var glanceHoldState: GlanceHoldState
    @State private var playbackCoordinator: PlaybackCoordinator

    init() {
        let settingsStore = UserDefaultsAttentionSettingsStore()
        let diagnosticSettingsStore = UserDefaultsDiagnosticSettingsStore()
        let loadedSettings = settingsStore.load()
        let loadedDiagnosticSettings = diagnosticSettingsStore.load()
        let diagnosticRecorder = LiveDiagnosticRecorder(mode: loadedDiagnosticSettings.diagnosticMode)
        let bridgeClient = IINAPluginBridgeClient(url: URL(string: "ws://127.0.0.1:47873")!)
        self.settingsStore = settingsStore
        self.diagnosticSettingsStore = diagnosticSettingsStore
        self.diagnosticSettings = loadedDiagnosticSettings
        self.diagnosticRecorder = diagnosticRecorder
        self.bridgeClient = bridgeClient
        self.monitor = AttentionMonitor(
            permissionProvider: CameraPermissionClient.live,
            settingsStore: settingsStore,
            capture: LiveCameraFrameCapture(),
            analyzer: AttentionAnalyzerFactory.live(),
            diagnosticRecorder: diagnosticRecorder,
            diagnosticMode: loadedDiagnosticSettings.diagnosticMode
        )
        _glanceHoldState = State(initialValue: GlanceHoldState(mode: loadedSettings.mode, settings: loadedSettings))
        _playbackCoordinator = State(initialValue: PlaybackCoordinator(
            mode: loadedSettings.mode,
            adapter: IINAPluginBridgeAdapter(client: bridgeClient),
            diagnosticRecorder: diagnosticRecorder,
            diagnosticMode: loadedDiagnosticSettings.diagnosticMode
        ))
    }

    var body: some Scene {
        MenuBarExtra(GlanceHoldStrings.text(.appName), systemImage: "display") {
            GlanceHoldMenu(
                state: $glanceHoldState,
                monitor: monitor,
                bridgeClient: bridgeClient,
                diagnosticSettingsStore: diagnosticSettingsStore,
                diagnosticSettings: diagnosticSettings,
                diagnosticRecorder: diagnosticRecorder,
                diagnosticMode: diagnosticSettings.diagnosticMode,
                restartRequester: LiveAppRestartRequester(),
                playbackCoordinator: $playbackCoordinator
            )
        }

        Window(GlanceHoldStrings.text(.aboutWindowTitle), id: "about") {
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
            GlanceHoldStrings.text(.actionCalibrate)
        case .recalibrate:
            GlanceHoldStrings.text(.actionRecalibrate)
        case .resetCalibration:
            GlanceHoldStrings.text(.actionResetCalibration)
        case .enable:
            GlanceHoldStrings.text(.actionEnableMonitoring)
        case .disable:
            GlanceHoldStrings.text(.actionDisableMonitoring)
        case .wait:
            GlanceHoldStrings.text(.actionWaitingCameraPermission)
        case .openCameraSettings:
            GlanceHoldStrings.text(.actionOpenCameraSettings)
        }
    }

    var isEnabled: Bool {
        self != .wait
    }
}

private enum MonitoringStopSource {
    case userRequested
    case manualPlayerTakeover
}

private struct GlanceHoldMenu: View {
    @Binding var state: GlanceHoldState
    let monitor: AttentionMonitor
    let bridgeClient: IINAPluginBridgeClienting
    let diagnosticSettingsStore: DiagnosticSettingsStoring
    let diagnosticSettings: DiagnosticSettings
    let diagnosticRecorder: DiagnosticRecording
    let diagnosticMode: DiagnosticMode
    let restartRequester: AppRestartRequesting
    @Binding var playbackCoordinator: PlaybackCoordinator
    @State private var permissionRequestID: UUID?
    @State private var playbackStatusStreamTask: Task<Void, Never>?
    @State private var playbackAttentionTask: Task<Void, Never>?
    @State private var monitoringToggleRequestTask: Task<Void, Never>?
    @State private var playbackSemanticDeduper = PlaybackSemanticDeduper()
    @Environment(\.openWindow) private var openWindow

    private let playbackStatusStreamReconnectIntervalNanoseconds: UInt64 = 1_000_000_000
    private let monitoringToggleReconnectIntervalNanoseconds: UInt64 = 10_000_000_000

    private var primaryAction: GlanceHoldPrimaryAction {
        GlanceHoldPrimaryAction.resolve(for: state.status, hasCalibration: state.hasCalibration)
    }

    private var tuningPresentation: TuningMenuPresentation {
        TuningMenuPresentation(settings: state.settings)
    }

    private var diagnosticModePresentation: DiagnosticModeMenuPresentation {
        DiagnosticModeMenuPresentation(settings: diagnosticSettings)
    }

    var body: some View {
        Group {
            Text(GlanceHoldStrings.format(.menuStatusFormat, state.status.visibleTitle))
                .accessibilityLabel(GlanceHoldStrings.format(.accessibilityStatusFormat, state.status.visibleTitle))

            if state.status == .cameraPermissionNeeded {
                Text(GlanceHoldStrings.text(.privacyPermissionExplanation))
                    .foregroundStyle(.secondary)
            } else if !state.status.detailText.isEmpty {
                Text(state.status.detailText)
                    .foregroundStyle(state.status == .cameraPermissionDenied ? .orange : .secondary)
            }

            Divider()

            if let playerStatus = state.playerStatus {
                Text(GlanceHoldStrings.format(.menuPlayerFormat, playerStatus.visibleTitle))
                    .accessibilityLabel(GlanceHoldStrings.format(.accessibilityPlayerFormat, playerStatus.visibleTitle))

                if !playerStatus.detailText.isEmpty {
                    Text(playerStatus.detailText)
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            if let lastActionMenuText = state.lastActionMenuText {
                Text(lastActionMenuText)
                    .foregroundStyle(.secondary)

                Divider()
            }

            Button(primaryAction.title) {
                performPrimaryAction(primaryAction)
            }
            .disabled(!primaryAction.isEnabled)

            Divider()

            Picker(ModeMenuPresentation.title(for: state.mode), selection: modeBinding) {
                Text(MonitoringMode.speedControl.displayName).tag(MonitoringMode.speedControl)
                Text(MonitoringMode.pauseResume.displayName).tag(MonitoringMode.pauseResume)
            }

            Divider()

            Text(GlanceHoldMenuCopy.tuningSectionTitle)
                .foregroundStyle(.secondary)

            Picker(tuningPresentation.sensitivityTitle, selection: sensitivityBinding) {
                ForEach(AttentionSensitivity.allCases, id: \.self) { sensitivity in
                    Text(sensitivity.displayName).tag(sensitivity)
                }
            }

            Picker(tuningPresentation.speedControlAwayDelayTitle, selection: speedControlAwayDelayBinding) {
                ForEach(tuningPresentation.speedControlAwayDelayOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Picker(tuningPresentation.pauseResumeAwayDelayTitle, selection: pauseResumeAwayDelayBinding) {
                ForEach(tuningPresentation.pauseResumeAwayDelayOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }

            Picker(tuningPresentation.recoveryDelayTitle, selection: recoveryDelayBinding) {
                ForEach(tuningPresentation.recoveryDelayOptions) { option in
                    Text(option.title).tag(option.value)
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

            Divider()

            Toggle(diagnosticModePresentation.title, isOn: diagnosticModeBinding)

            Button(GlanceHoldStrings.text(.menuAbout)) {
                openWindow(id: "about")
            }

            Button(GlanceHoldStrings.text(.menuQuit)) {
                let cleanupPlan = MonitoringToggleController.cleanupPlan(for: .quit)
                performLifecycleCleanup(cleanupPlan)
                if cleanupPlan.terminateAfterCleanup {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .onAppear {
            installMonitorStateHandler()
            startPlaybackStatusUpdates()
            startMonitoringToggleRequestHandling()
        }
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
                replacePlaybackCoordinator(mode: mode)
            }
        )
    }

    private var diagnosticModeBinding: Binding<Bool> {
        Binding(
            get: {
                diagnosticModePresentation.isSelected
            },
            set: { _ in
                toggleDiagnosticMode()
            }
        )
    }

    private var sensitivityBinding: Binding<AttentionSensitivity> {
        Binding(
            get: {
                state.settings.sensitivity
            },
            set: { sensitivity in
                updateSettings(state.settings.withSensitivity(sensitivity))
            }
        )
    }

    private var speedControlAwayDelayBinding: Binding<Double> {
        Binding(
            get: {
                TuningMenuPresentation.normalizedDelaySelection(state.settings.speedControlAwayDelay)
            },
            set: { delay in
                var settings = state.settings
                settings.speedControlAwayDelay = delay
                updateSettings(settings)
            }
        )
    }

    private var pauseResumeAwayDelayBinding: Binding<Double> {
        Binding(
            get: {
                TuningMenuPresentation.normalizedDelaySelection(state.settings.pauseResumeAwayDelay)
            },
            set: { delay in
                var settings = state.settings
                settings.pauseResumeAwayDelay = delay
                updateSettings(settings)
            }
        )
    }

    private var recoveryDelayBinding: Binding<Double> {
        Binding(
            get: {
                TuningMenuPresentation.normalizedDelaySelection(state.settings.recoveryDelay)
            },
            set: { delay in
                var settings = state.settings
                settings.recoveryDelay = delay
                updateSettings(settings)
            }
        )
    }

    private func toggleDiagnosticMode() {
        do {
            try DiagnosticModeMenuAction.toggle(
                settingsStore: diagnosticSettingsStore,
                restartRequester: restartRequester,
                restartFailureHandler: {
                    Task { @MainActor in
                        state.status = .cameraUnavailable
                    }
                }
            )
        } catch {
            state.status = .cameraUnavailable
        }
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
            stopMonitoring(source: .userRequested)
        case .wait:
            break
        case .openCameraSettings:
            openCameraSettings()
        }
    }

    private func performMonitoringToggleRequest() {
        let action = MonitoringToggleController.resolveAction(for: state)
        performPrimaryAction(action)
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
        alert.addButton(withTitle: GlanceHoldStrings.text(.alertCancel))
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
        alert.messageText = GlanceHoldStrings.text(.alertRecalibrationRecommended)
        alert.informativeText = GlanceHoldMenuCopy.marginalReplacementPrompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: GlanceHoldMenuCopy.keepCurrentCalibrationButton)
        alert.addButton(withTitle: GlanceHoldMenuCopy.useNewCalibrationButton)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func stopMonitoring(source: MonitoringStopSource) {
        switch source {
        case .userRequested:
            performLifecycleCleanup(MonitoringToggleController.cleanupPlan(for: .userDisable))
            state.stopMonitoringAfterUserRequest()
        case .manualPlayerTakeover:
            permissionRequestID = nil
            monitor.stopMonitoring()
            playbackCoordinator.stopMonitoring()
            state.stopMonitoringAfterManualPlayerTakeover()
        }
    }

    private func performLifecycleCleanup(_ plan: MonitoringLifecycleCleanupPlan) {
        if plan.cancelPermissionRequest {
            permissionRequestID = nil
        }
        if plan.stopPlaybackStatusUpdates {
            stopPlaybackStatusUpdates()
        }
        if plan.stopMonitoringToggleRequests {
            stopMonitoringToggleRequestHandling()
        }
        if plan.stopPlaybackCoordinator {
            stopPlaybackAttentionHandling()
            playbackCoordinator.stopMonitoring()
        }
        if plan.stopAttentionMonitor {
            monitor.stopMonitoring()
        }
    }

    private func installMonitorStateHandler() {
        installPlaybackCoordinatorStateHandler()
        let coordinator = playbackCoordinator
        let currentDiagnosticSession = monitor.currentDiagnosticSession
        coordinator.setDiagnosticSession(currentDiagnosticSession)
        resetPlaybackSemanticDeduper(for: currentDiagnosticSession)
        monitor.diagnosticSessionDidChange = { session in
            coordinator.setDiagnosticSession(session)
            Task { @MainActor in
                resetPlaybackSemanticDeduper(for: session)
            }
        }
        refreshPlaybackCoordinator(coordinator)
        monitor.stateDidChange = { monitorState, settings in
            Task { @MainActor in
                state.updateSettings(settings)
                state.apply(monitorState: monitorState)

                guard let attentionState = Self.playbackAttentionState(for: monitorState) else {
                    return
                }

                guard playbackSemanticDeduper.shouldEmit(attentionState) else {
                    if playbackSemanticDeduper.suppressionReason(for: attentionState) == .repeatedStableStateNoCommand {
                        coordinator.recordSuppressedRepeatedStableStateNoCommand(attentionState)
                    }
                    return
                }

                sendAttentionState(attentionState, to: coordinator)
            }
        }
    }

    private func resetPlaybackSemanticDeduper(for session: DiagnosticSession?) {
        guard let session else {
            playbackSemanticDeduper.endSession()
            return
        }

        playbackSemanticDeduper.startSession(session.id)
    }

    private func installPlaybackCoordinatorStateHandler() {
        playbackCoordinator.stateDidChange = { coordinatorState in
            Task { @MainActor in
                state.apply(playerControlState: coordinatorState)
            }
        }
        playbackCoordinator.playbackActionDidComplete = { action in
            Task { @MainActor in
                state.recordLastAction(action.lastAction)
            }
        }
        playbackCoordinator.stopMonitoringRequested = { _ in
            Task { @MainActor in
                stopMonitoring(source: .manualPlayerTakeover)
            }
        }
    }

    private func refreshPlaybackCoordinator(_ coordinator: PlaybackCoordinator) {
        Task {
            await coordinator.refreshPlayerState()
        }
    }

    private func sendAttentionState(_ attentionState: DebouncedAttentionState, to coordinator: PlaybackCoordinator) {
        playbackAttentionTask?.cancel()
        playbackAttentionTask = Task {
            await coordinator.handleAttentionState(attentionState)
        }
    }

    private func startPlaybackStatusUpdates() {
        guard playbackStatusStreamTask == nil else {
            return
        }

        let coordinator = playbackCoordinator
        playbackStatusStreamTask = Task {
            while !Task.isCancelled {
                await coordinator.observePlayerStatusUpdates()
                if Task.isCancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: playbackStatusStreamReconnectIntervalNanoseconds)
            }
        }
    }

    private func startMonitoringToggleRequestHandling() {
        guard monitoringToggleRequestTask == nil else {
            return
        }

        monitoringToggleRequestTask = Task {
            while !Task.isCancelled {
                for await _ in bridgeClient.monitoringToggleRequests() {
                    if Task.isCancelled {
                        return
                    }

                    await MainActor.run {
                        performMonitoringToggleRequest()
                    }
                }

                if Task.isCancelled {
                    return
                }

                try? await Task.sleep(nanoseconds: monitoringToggleReconnectIntervalNanoseconds)
            }
        }
    }

    private func stopPlaybackStatusUpdates() {
        playbackStatusStreamTask?.cancel()
        playbackStatusStreamTask = nil
    }

    private func stopPlaybackAttentionHandling() {
        playbackAttentionTask?.cancel()
        playbackAttentionTask = nil
    }

    private func stopMonitoringToggleRequestHandling() {
        monitoringToggleRequestTask?.cancel()
        monitoringToggleRequestTask = nil
    }

    private func replacePlaybackCoordinator(mode: MonitoringMode) {
        stopPlaybackStatusUpdates()
        stopPlaybackAttentionHandling()
        playbackCoordinator.stateDidChange = nil
        playbackCoordinator.stopMonitoringRequested = nil
        playbackCoordinator.playbackActionDidComplete = nil
        playbackCoordinator.stopMonitoring()
        playbackCoordinator = makePlaybackCoordinator(mode: mode)
        state.playerStatus = nil
        installMonitorStateHandler()
        startPlaybackStatusUpdates()
    }

    private func makePlaybackCoordinator(mode: MonitoringMode) -> PlaybackCoordinator {
        PlaybackCoordinator(
            mode: mode,
            adapter: IINAPluginBridgeAdapter(client: bridgeClient),
            diagnosticRecorder: diagnosticRecorder,
            diagnosticMode: diagnosticMode
        )
    }

    private static func playbackAttentionState(for monitorState: AttentionMonitorState) -> DebouncedAttentionState? {
        switch monitorState {
        case .facing:
            .facing
        case .lookingAway:
            .lookingAway
        case .noFaceDetected:
            .noFaceDetected
        case .recovering:
            .recovering
        case .unavailable:
            .unavailable
        case .off, .needsCalibration, .calibrating, .ready, .monitoringPendingFirstSample,
            .cameraPermissionDenied, .cameraUnavailable, .calibrationFailed:
            nil
        }
    }
}

private extension PlaybackCompletedAction {
    var lastAction: LastAction {
        switch self {
        case .heldSpeedAtOne:
            .heldSpeedAtOne
        case let .restoredSpeed(speed):
            .restoredSpeed(speed)
        case .pausedByGlanceHold:
            .pausedByGlanceHold
        case .resumedPlayback:
            .resumedPlayback
        }
    }
}
